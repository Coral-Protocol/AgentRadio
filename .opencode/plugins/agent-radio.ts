import type { Plugin } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"
import * as fs from "fs"
import * as path from "path"
import * as os from "os"

// ── Radio core (mirrors scripts/radio_main.py + opencode core) ──
const VALID_THREAD = /^[a-zA-Z0-9\-_.]+$/
const POLL_DEFAULT = 1.0
const MAX_MSGS_PER_THREAD_FILE = 1000
const MAX_STATE_INJECTION = 30
const MAX_TOOL_READ = 100

function getDefaultRoot(worktree: string, directory: string): string {
  const envRoot = process.env.RADIO_ROOT
  if (envRoot && envRoot.trim()) return envRoot
  const base = worktree || directory || process.cwd()
  let sanitized = base.replace(/[^a-zA-Z0-9]/g, "-").replace(/^-+/, "").replace(/-+$/, "")
  if (!sanitized) sanitized = "default"
  if (sanitized.length > 80) sanitized = sanitized.slice(0, 80)
  let hash = 0
  for (let i = 0; i < base.length; i++) hash = ((hash * 31) + base.charCodeAt(i)) >>> 0
  const suffix = hash.toString(16).slice(0, 6)
  return path.join(os.homedir(), ".cache", "opencode", "radio", `${sanitized}-${suffix}`)
}

function resolveRoot(explicit?: string, worktree?: string, directory?: string): string {
  if (explicit && explicit.trim()) return explicit
  if (process.env.RADIO_ROOT && process.env.RADIO_ROOT.trim()) return process.env.RADIO_ROOT
  return getDefaultRoot(worktree || "", directory || "")
}

function threadFile(rootDir: string, name: string): string {
  if (!name || !VALID_THREAD.test(name)) throw new Error(`invalid thread name: ${JSON.stringify(name)}`)
  return path.join(rootDir, "threads", name + ".jsonl")
}

function ensureRadio(rootDir: string) {
  fs.mkdirSync(path.join(rootDir, "threads"), { recursive: true })
  const metaPath = path.join(rootDir, "meta.json")
  if (!fs.existsSync(metaPath)) {
    const meta = { created_at: new Date().toISOString(), protocol: "agent-radio/passive", version: 3, core: true }
    fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2), "utf-8")
  }
}

type RadioMsg = {
  id: string
  ts: number
  from: string
  mentions: string[]
  content: string
  _thread: string
}

function loadAll(rootDir: string): RadioMsg[] {
  const tdir = path.join(rootDir, "threads")
  const out: RadioMsg[] = []
  if (!fs.existsSync(tdir)) return out
  let entries: string[] = []
  try { entries = fs.readdirSync(tdir).sort() } catch { return out }
  for (const fname of entries) {
    if (!fname.endsWith(".jsonl")) continue
    const full = path.join(tdir, fname)
    let text = ""
    try { text = fs.readFileSync(full, "utf-8") } catch { continue }
    for (const line of text.split("\n")) {
      const s = line.trim()
      if (!s) continue
      try {
        const m = JSON.parse(s)
        m._thread = fname.slice(0, -6)
        out.push(m as RadioMsg)
      } catch { /* skip broken */ }
    }
  }
  out.sort((a, b) => (a.ts - b.ts) || a.id.localeCompare(b.id))
  return out
}

function loadThread(rootDir: string, thread: string): RadioMsg[] {
  const p = threadFile(rootDir, thread)
  if (!fs.existsSync(p)) return []
  const out: RadioMsg[] = []
  for (const line of fs.readFileSync(p, "utf-8").split("\n")) {
    const s = line.trim(); if (!s) continue
    try { const m = JSON.parse(line); m._thread = thread; out.push(m as RadioMsg) } catch {}
  }
  out.sort((a,b)=>(a.ts-b.ts)||a.id.localeCompare(b.id))
  return out
}

function fmtMessage(m: RadioMsg): string {
  const mentions = (m.mentions || []).map(x => `@${x}`).join(",")
  let head = `[${m._thread}] ${m.from || "?"}`
  if (mentions) head += ` -> ${mentions}`
  const ts = (m.ts || 0) / 1e9
  const stamp = new Date(ts * 1000).toTimeString().slice(0, 8)
  const body = (m.content || "").replace(/\n/g, "\n  ")
  return `${head} (${stamp})\n  ${body}`
}

function fmtState(msgs: RadioMsg[]): string {
  if (!msgs.length) return "(no messages yet)"
  const out: string[] = []
  let current = ""
  for (const m of msgs) {
    if (m._thread !== current) {
      out.push(`## thread: ${m._thread}`)
      current = m._thread
    }
    out.push(fmtMessage(m))
  }
  return out.join("\n")
}

function summarizeForSystem(msgs: RadioMsg[], root: string): string {
  const total = msgs.length
  let body = ""
  if (total === 0) body = "(no messages yet — send the first one with radio_send)"
  else if (total <= MAX_STATE_INJECTION) body = fmtState(msgs)
  else body = `(showing last ${MAX_STATE_INJECTION} of ${total} messages — ${total - MAX_STATE_INJECTION} older not shown)\n` + fmtState(msgs.slice(-MAX_STATE_INJECTION))
  return [`RADIO_ROOT=${root}`, body].join("\n")
}

function pruneIfNeeded(rootDir: string, thread: string) {
  try {
    const p = threadFile(rootDir, thread)
    if (!fs.existsSync(p)) return
    const lines = fs.readFileSync(p, "utf-8").split("\n").filter(l=>l.trim())
    if (lines.length <= MAX_MSGS_PER_THREAD_FILE) return
    // Archive oldest half
    const archiveDir = path.join(rootDir, "archive")
    fs.mkdirSync(archiveDir, { recursive: true })
    const toArchive = lines.slice(0, lines.length - MAX_MSGS_PER_THREAD_FILE)
    const keep = lines.slice(-MAX_MSGS_PER_THREAD_FILE)
    const stamp = new Date().toISOString().slice(0,10)
    const archivePath = path.join(archiveDir, `${thread}-${stamp}-${Date.now()}.jsonl`)
    fs.writeFileSync(archivePath, toArchive.join("\n")+"\n", "utf-8")
    fs.writeFileSync(p, keep.join("\n")+(keep.length?"\n":""), "utf-8")
  } catch { /* ignore pruning errors */ }
}

// Memory integration: append worklog discoveries to daily memory file (best-effort)
function appendToDailyMemory(worktree: string, directory: string, msg: RadioMsg) {
  try {
    // Only for worklog / planning / results threads that carry durable knowledge
    if (!["worklog","planning"].includes(msg._thread) && !msg._thread.startsWith("results-")) return
    const base = worktree || directory || process.cwd()
    let sanitized = base.replace(/[^a-zA-Z0-9]/g, "-").replace(/^-+/, "").replace(/-+$/, "")
    if (!sanitized) sanitized = "default"
    if (sanitized.length > 80) sanitized = sanitized.slice(0,80)
    let hash=0; for(let i=0;i<base.length;i++) hash=((hash*31)+base.charCodeAt(i))>>>0
    const suffix = hash.toString(16).slice(0,6)
    const memRoot = path.join(os.homedir(), ".cache", "opencode", "memory", `${sanitized}-${suffix}`)
    const today = new Date().toISOString().slice(0,10)
    const dailyPath = path.join(memRoot, "memory", `${today}.md`)
    fs.mkdirSync(path.dirname(dailyPath), { recursive: true })
    const line = `- [${new Date(msg.ts/1e6).toISOString()}] [radio:${msg._thread}] ${msg.from}: ${msg.content.replace(/\n/g," ")} ${msg.mentions.length?`(@${msg.mentions.join(",@")})`:""}\n`
    fs.appendFileSync(dailyPath, line, "utf-8")
  } catch {}
}

async function logInfo(client: any, service: string, msg: string, extra?: any, level: "info"|"warn"|"error"="info") {
  try { await client.app.log({ body: { service, level, message: msg, extra } }) } catch {}
}

export const AgentRadioPlugin: Plugin = async ({ project, directory, worktree, client, $ }) => {
  const defaultRoot = getDefaultRoot(worktree, directory)
  try { ensureRadio(process.env.RADIO_ROOT || defaultRoot) } catch {}

  return {
    "shell.env": async (_input, output) => {
      if (!output.env.RADIO_ROOT) {
        const cur = process.env.RADIO_ROOT
        output.env.RADIO_ROOT = cur && cur.trim() ? cur : defaultRoot
        output.env.RADIO_POLL_SEC = output.env.RADIO_POLL_SEC || "1.0"
        try { ensureRadio(output.env.RADIO_ROOT) } catch {}
      }
      // Also inject MEMORY root for downstream memory plugin (idempotent)
      if (!output.env.OPENCODE_MEMORY_ROOT) {
        const base = worktree || directory || process.cwd()
        let sanitized = base.replace(/[^a-zA-Z0-9]/g, "-").replace(/^-+/, "").replace(/-+$/, "")
        if (!sanitized) sanitized="default"
        if (sanitized.length>80) sanitized=sanitized.slice(0,80)
        let hash=0; for(let i=0;i<base.length;i++) hash=((hash*31)+base.charCodeAt(i))>>>0
        output.env.OPENCODE_MEMORY_ROOT = path.join(os.homedir(), ".cache", "opencode", "memory", `${sanitized}-${hash.toString(16).slice(0,6)}`)
      }
    },

    "experimental.chat.system.transform": async (_input, output) => {
      try {
        // Dedup: skip if already injected by sibling plugin (global+project double)
        if (output.system.some(s => s.includes("AgentRadio — passive awareness"))) return
        const root = process.env.RADIO_ROOT || defaultRoot
        const hasRadioDir = fs.existsSync(path.join(root, "threads")) || fs.existsSync(path.join(root, "meta.json"))
        const msgs = hasRadioDir ? loadAll(root) : []
        const hasTraffic = msgs.length > 0
        const banner = [
          "## 📻 AgentRadio — passive awareness (always-on, core)",
          "You share a file-backed radio bus with every other opencode session/agent touching this worktree.",
          `Bus: RADIO_ROOT=${root}  (tools: radio_send / radio_read / radio_threads / radio_init ; shell: ~/.config/opencode/skills/agent-radio/scripts/radio.sh)`,
          "Rule: keep working while you listen. Do NOT block waiting for replies. Send is fire-and-forget.",
          "At each step boundary you ALREADY see new messages below (injected). No extra tool call needed to stay aware.",
          "Triage: URGENT: = handle NOW if it affects in-flight work; FYI: = note & continue; else reply at next natural break.",
          "Escalate live: findings bearing on peer's sub-question (mention them), contradictions with plan, obstacles, dead ends you abandoned.",
          hasTraffic ? "" : "bus empty → solo/short tasks may ignore; long/multi-agent tasks: init threads via radio_send.",
        ].filter(Boolean).join("\n")

        let injection = banner
        if (hasTraffic) {
          injection += "\n\n### Current bus state (auto-injected, passive — no tool call spent)\n" + summarizeForSystem(msgs, root)
          // Highlight URGENT mentions
          const urgents = msgs.filter(m => m.content.startsWith("URGENT:")).slice(-5)
          if (urgents.length) {
            injection += "\n\n### ⚠️ Recent URGENT\n" + urgents.map(fmtMessage).join("\n")
          }
        }
        if (hasTraffic || hasRadioDir) {
          injection += "\n\n### When collaborating (5-phase, only if task warrants)"
          injection += "\nP1 Explore (watcher already passive) → P2 Divide (planning, unanimous APPROVE) → P3 Execute (post live to worklog, mention peers) → P4 Review (own results thread, cross-check) → P5 Submit (assembler, full draft, unanimous). Decisions in planning, live findings in worklog — keep them separate."
        }
        output.system.push(injection)
      } catch (e: any) {
        try { await logInfo(client, "agent-radio", `system.transform failed: ${e?.message || e}`) } catch {}
      }
    },

    "experimental.session.compacting": async (_input, output) => {
      try {
        // Dedup: skip if already injected by sibling plugin (global+project double)
        if (output.system.some(s => s.includes("AgentRadio — passive awareness"))) return
        const root = process.env.RADIO_ROOT || defaultRoot
        const tdir = path.join(root, "threads")
        if (!fs.existsSync(tdir)) return
        const msgs = loadAll(root)
        if (!msgs.length) return
        const dump = summarizeForSystem(msgs, root)
        output.context.push(
          "## 📻 Radio bus — preserved across compaction (copy evidence verbatim when resuming)\n" + dump +
          "\n\nRule after compaction: re-read via radio_read before asserting about teammates' findings."
        )
      } catch {}
    },

    event: async ({ event }) => {
      if (event.type === "session.created") {
        try {
          const root = process.env.RADIO_ROOT || defaultRoot
          ensureRadio(root)
          await logInfo(client, "agent-radio", `session created — radio ready at ${root}`, { root })
        } catch {}
      }
      // Passive notification for URGENT messages: surface via warn log
      if (event.type === "session.idle" || event.type === "session.updated") {
        try {
          const root = process.env.RADIO_ROOT || defaultRoot
          const msgs = loadAll(root)
          const last = msgs[msgs.length-1]
          if (last && last.content.startsWith("URGENT:") && Date.now()*1e6 - last.ts < 60*1e9) {
            await logInfo(client, "agent-radio", `URGENT on [${last._thread}] from ${last.from}: ${last.content.slice(0,120)}`, { thread: last._thread, from: last.from }, "warn")
          }
        } catch {}
      }
    },

    tool: {
      radio_init: tool({
        description: "Initialize the AgentRadio bus (idempotent, core). Returns RADIO_ROOT. Autocreates on first send if you skip this.",
        args: {
          root: tool.schema.string().optional().describe("Optional explicit RADIO_ROOT path. Defaults to worktree-scoped cache (~/.cache/opencode/radio/…) or $RADIO_ROOT."),
        },
        async execute(args, ctx) {
          const root = resolveRoot(args.root, ctx.worktree, ctx.directory)
          ensureRadio(root)
          return `radio ready at ${root}\nThreads dir: ${path.join(root, "threads")}\nArchive dir: ${path.join(root, "archive")}\nPeers should export same RADIO_ROOT. Shell helper: ~/.config/opencode/skills/agent-radio/scripts/radio.sh`
        },
      }),

      radio_send: tool({
        description: "Send to AgentRadio bus (fire-and-forget, non-blocking, core). Use for planning decisions, worklog discoveries, reviews, approvals. Mention peers with mentions csv so their watcher wakes at next step boundary. Messages are also auto-appended to daily memory for durability.",
        args: {
          thread: tool.schema.string().describe("Thread/topic, e.g. planning, worklog, results-agent-2. Valid chars: a-z A-Z 0-9 - _ ."),
          content: tool.schema.string().describe("Message body. Prefix URGENT: if it affects peer's in-flight work, FYI: if purely informational."),
          from: tool.schema.string().optional().describe("Sender id, e.g. agent-1, assembler. Defaults to 'agent'. Use distinct ids per peer."),
          mentions: tool.schema.string().optional().describe("Comma-separated agent ids to mention, e.g. agent-2,agent-3."),
        },
        async execute(args, ctx) {
          const root = resolveRoot(undefined, ctx.worktree, ctx.directory)
          ensureRadio(root)
          const thread = args.thread.trim()
          if (!VALID_THREAD.test(thread)) throw new Error(`invalid thread name ${JSON.stringify(thread)}`)
          const sender = (args.from && args.from.trim()) || "agent"
          const mentions = (args.mentions || "").split(",").map(s => s.trim()).filter(Boolean)
          const content = args.content
          if (!content || !content.trim()) throw new Error("content must be non-empty")
          const p = threadFile(root, thread)
          fs.mkdirSync(path.dirname(p), { recursive: true })
          const msg: RadioMsg = {
            id: `m-${Date.now()}-${process.pid}-${Math.random().toString(16).slice(2, 6)}`,
            ts: Date.now() * 1e6,
            from: sender,
            mentions,
            content,
            _thread: thread,
          }
          fs.appendFileSync(p, JSON.stringify({ id: msg.id, ts: msg.ts, from: msg.from, mentions: msg.mentions, content: msg.content }) + "\n", "utf-8")
          pruneIfNeeded(root, thread)
          appendToDailyMemory(ctx.worktree, ctx.directory, msg)
          const level = content.startsWith("URGENT:") ? "warn" : "info"
          try { await logInfo(client, "agent-radio", `sent [${thread}] ${sender} -> ${mentions.join(",") || "(broadcast)"}`, { thread, sender }, level as any) } catch {}
          return JSON.stringify({ sent: true, thread, id: msg.id, root, mentions })
        },
      }),

      radio_read: tool({
        description: "Read full AgentRadio bus state — all threads, chronological. Self-contained dump; no per-thread call needed. Use after compaction or before assembling final answer.",
        args: {
          root: tool.schema.string().optional().describe("Optional RADIO_ROOT override."),
          thread: tool.schema.string().optional().describe("If set, only read that thread (e.g. worklog). Otherwise all threads."),
          limit: tool.schema.number().optional().describe("Max messages to show from tail (default 100, 0=all)."),
        },
        async execute(args, ctx) {
          const root = resolveRoot(args.root, ctx.worktree, ctx.directory)
          let msgs: RadioMsg[]
          if (args.thread && args.thread.trim()) {
            if (!VALID_THREAD.test(args.thread.trim())) throw new Error("invalid thread")
            msgs = loadThread(root, args.thread.trim())
          } else {
            msgs = loadAll(root)
          }
          if (!msgs.length) return `(no messages yet) RADIO_ROOT=${root}` + (args.thread?` thread=${args.thread}`:"")
          const lim = args.limit ?? MAX_TOOL_READ
          if (lim === 0 || msgs.length <= lim) return `RADIO_ROOT=${root}\n` + fmtState(msgs)
          const shown = msgs.slice(-lim)
          return `RADIO_ROOT=${root}\n(showing last ${lim} of ${msgs.length} messages)\n` + fmtState(shown)
        },
      }),

      radio_threads: tool({
        description: "List AgentRadio thread names present on the bus.",
        args: {
          root: tool.schema.string().optional().describe("Optional RADIO_ROOT override."),
        },
        async execute(args, ctx) {
          const root = resolveRoot(args.root, ctx.worktree, ctx.directory)
          const tdir = path.join(root, "threads")
          if (!fs.existsSync(tdir)) return `(no threads yet) RADIO_ROOT=${root}`
          const names = fs.readdirSync(tdir).filter(f => f.endsWith(".jsonl")).map(f => f.slice(0, -6)).sort()
          if (!names.length) return `(no threads yet) RADIO_ROOT=${root}`
          // Include message counts
          const details = names.map(n => {
            try { const c = fs.readFileSync(path.join(tdir, n+".jsonl"), "utf-8").split("\n").filter(l=>l.trim()).length; return `${n} (${c})` } catch { return n }
          })
          return `RADIO_ROOT=${root}\n` + details.join("\n")
        },
      }),

      radio_status: tool({
        description: "Show AgentRadio bus status: threads, counts, archive, memory integration.",
        args: {
          root: tool.schema.string().optional().describe("Optional RADIO_ROOT override."),
        },
        async execute(args, ctx) {
          const root = resolveRoot(args.root, ctx.worktree, ctx.directory)
          const tdir = path.join(root, "threads")
          const archiveDir = path.join(root, "archive")
          const hasRadio = fs.existsSync(tdir)
          const threads = hasRadio ? fs.readdirSync(tdir).filter(f=>f.endsWith(".jsonl")).map(f=>f.slice(0,-6)).sort() : []
          const total = hasRadio ? threads.reduce((acc,n)=>{ try{ return acc+fs.readFileSync(path.join(tdir,n+".jsonl"),"utf-8").split("\n").filter(l=>l.trim()).length } catch {return acc}},0) : 0
          const archived = fs.existsSync(archiveDir) ? fs.readdirSync(archiveDir).length : 0
          const memRoot = process.env.OPENCODE_MEMORY_ROOT || (()=>{ const b=ctx.worktree||ctx.directory||process.cwd(); let s=b.replace(/[^a-zA-Z0-9]/g,"-").replace(/^-+/,"").replace(/-+$/,""); if(!s) s="default"; if(s.length>80) s=s.slice(0,80); let h=0; for(let i=0;i<b.length;i++) h=((h*31)+b.charCodeAt(i))>>>0; return path.join(os.homedir(), ".cache","opencode","memory", `${s}-${h.toString(16).slice(0,6)}`) })()
          return [
            `RADIO_ROOT=${root}`,
            `threads: ${threads.length} (${threads.join(", ") || "none"})`,
            `total messages: ${total}`,
            `archived files: ${archived}`,
            `memory integration: ${memRoot} (daily appended)`,
            `core: passive injection active (system.transform)`,
          ].join("\n")
        },
      }),

      radio_clear: tool({
        description: "Clear AgentRadio bus (archive current threads, keep last 10 per thread). Use with caution — for resetting a polluted bus between tasks.",
        args: {
          root: tool.schema.string().optional().describe("Optional RADIO_ROOT override."),
          confirm: tool.schema.string().describe("Must be 'yes' to confirm."),
        },
        async execute(args, ctx) {
          if (args.confirm !== "yes") throw new Error("must confirm with confirm='yes'")
          const root = resolveRoot(args.root, ctx.worktree, ctx.directory)
          const tdir = path.join(root, "threads")
          if (!fs.existsSync(tdir)) return `no bus at ${root}`
          for (const f of fs.readdirSync(tdir).filter(f=>f.endsWith(".jsonl"))) {
            const p = path.join(tdir,f)
            const lines = fs.readFileSync(p,"utf-8").split("\n").filter(l=>l.trim())
            if (lines.length<=10) continue
            const archiveDir = path.join(root, "archive")
            fs.mkdirSync(archiveDir,{recursive:true})
            const archivePath = path.join(archiveDir, `${f.slice(0,-6)}-clear-${Date.now()}.jsonl`)
            fs.writeFileSync(archivePath, lines.slice(0,-10).join("\n")+"\n","utf-8")
            fs.writeFileSync(p, lines.slice(-10).join("\n")+"\n","utf-8")
          }
          return `cleared bus at ${root} (kept last 10 per thread, archived rest)`
        },
      }),

      radio_wait: tool({
        description: "Blocking wait for mention/new traffic (foreground, L2). Prefer PASSIVE — you already see messages auto-injected. Only use to explicitly block.",
        args: {
          me: tool.schema.string().describe("Your agent id to watch for, e.g. agent-1."),
          timeout: tool.schema.number().optional().describe("Seconds to wait, default 30, max 120."),
          root: tool.schema.string().optional().describe("Optional RADIO_ROOT override."),
        },
        async execute(args, ctx) {
          const root = resolveRoot(args.root, ctx.worktree, ctx.directory)
          const me = args.me.trim()
          if (!me) throw new Error("me must be non-empty")
          const maxWait = Math.min(Math.max(args.timeout ?? 30, 1), 120)
          const poll = Number(process.env.RADIO_POLL_SEC || POLL_DEFAULT)
          const baseline = loadAll(root).length
          const deadline = Date.now() + maxWait * 1000
          while (Date.now() < deadline) {
            const msgs = loadAll(root)
            const fresh = msgs.slice(baseline)
            for (const m of fresh) {
              const mentioned = (m.mentions || []).includes(me) || (m.content || "").includes(`@${me}`)
              if (mentioned) return `MENTION RECEIVED for @${me}:\n` + fmtMessage(m) + "\n\n=== CURRENT STATE ===\n" + fmtState(msgs)
            }
            if (fresh.length) return `NEW MESSAGE(S) FOUND (baseline ${baseline}):\n` + fmtMessage(fresh[0]) + "\n\n=== CURRENT STATE ===\n" + fmtState(msgs)
            await new Promise(r => setTimeout(r, poll * 1000))
          }
          const msgs = loadAll(root)
          return `(timeout ${maxWait}s — nothing new after baseline=${baseline}) RADIO_ROOT=${root}\n` + fmtState(msgs)
        },
      }),
    },
  }
}
