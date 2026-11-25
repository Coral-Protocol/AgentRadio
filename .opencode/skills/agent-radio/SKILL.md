---
name: agent-radio
description: Run long-horizon multi-agent collaboration with passive awareness (AgentRadio method). Use when coordinating several coding agents (or subagents/sessions) on one task — dividing work, negotiating a plan, sharing discoveries while working instead of blocking to listen, cross-reviewing results, and assembling a final submission. Triggers: multi-agent, team of agents, divide work, wait_for_mention, radio, worklog, five-phase protocol.
---

# AgentRadio — Passive Awareness for Multi-Agent Collaboration

A portable implementation of the protocol from
[AgentRadio](https://github.com/Coral-Protocol/AgentRadio)
(paper: [arXiv:2607.28430](https://arxiv.org/abs/2607.28430)): agents keep working **while**
they listen, because receiving messages runs as a background task instead of stealing a turn.
On SWE-Atlas QnA this single change took four agents from 51.6% → 62.1% task accuracy.

This folder needs no Docker, JDK, or message server. The "radio" is an append-only JSONL
directory driven by `scripts/radio.sh` (python3 stdlib only).

## When to reach for this

- One task, several agents/subagents/sessions that would otherwise duplicate work or
  discover the same bug twice.
- Long horizon (hours), where a discovery made at minute 10 should reach whoever needs it
  at minute 11 — not at the next phase boundary.
- You are the orchestrator/assembler, or you are ONE peer among several agent processes.

## The three primitives

```bash
scripts/radio.sh init                                  # once, per team session
scripts/radio.sh send <thread> <me> "<content>" [--mentions agent-2,agent-3]
scripts/radio.sh wait <me> [--max-wait 60]             # the watcher
scripts/radio.sh read                                  # full state dump
```

Set `RADIO_ROOT=/some/dir` so every teammate points at the same bus (default `.radio/`,
outside any repo you plan to commit). `send` is fire-and-forget: it returns immediately.
`wait` blocks until someone mentions `<me>` OR any new message appears; its output is
**self-contained** (the new message + a full dump of all threads), so a notified agent never
needs a second `read`.

## The watcher loop (this is the whole trick)

1. Start your watcher as a **background task** and keep exactly ONE running at all times:

   ```bash
   RADIO_ROOT=... scripts/radio.sh wait agent-2 --max-wait 300   # run in background
   ```

2. Keep working in the foreground. Never block on purpose. Never go deaf.
3. When the background task finishes: **first relaunch a fresh watcher** (never leave a
   gap, never run two at once), **then** read the finished output and handle what's new.
4. Triage without stopping: `URGENT:` = handle now, it affects your in-flight work;
   `FYI:` = note it and continue; no prefix = reply at your next natural break.
5. Never silently drop a message. If you defer one, write it down and come back before
   the next phase.
6. After a context compaction, your memory is lossy — re-run `read` and copy evidence
   verbatim from the dump before writing anything that depends on teammates' findings.

## The five-phase protocol

**P1 · Explore** — start your watcher, explore independently, draft the sub-questions you
see. Send nothing yet.

**P2 · Divide** — the assembler (agent-1) opens a `planning` thread. Everyone proposes
coverage; negotiate until the partition (a) covers ALL explicit and implicit sub-questions,
(b) keeps things that belong together with the same agent, (c) has every finding discussed.
Every agent posts `APPROVE` (mentioning everyone) before P3 starts. The assembler then
broadcasts the final plan and opens a shared `worklog` thread — decisions live in
`planning`, live discoveries live in `worklog`; keep them separate.

**P3 · Execute, with live sharing** — work your share independently. Post to `worklog`
the moment something happens, because sending costs you nothing and doesn't interrupt
anyone:
- a finding that bears on another agent's sub-question (mention them);
- anything contradicting the agreed plan or a teammate's claim (`URGENT:` if their
  in-flight work depends on it);
- obstacles — say exactly what you tried and how it failed;
- abandoned approaches, so nobody re-burns time on the same dead end.
Gather evidence with exact values, file paths, line numbers. If the task says run code,
actually run it.

**P4 · Review** — each agent broadcasts complete findings with evidence into its own
results thread. Reviewers check factual conflicts, thin evidence, and information gaps
("I saw X relevant to your area that you didn't mention"). Re-investigation sends the item
back to P3. Approve only when there are no unresolved conflicts and no open gaps.

**P5 · Submit** — only after unanimous approval, the assembler writes the FULL draft (not a
summary), everyone checks it against their own findings, and only then is it submitted.

## Invocation & roles (slash commands)

AgentRadio is driven by slash commands. The **team leader** invokes with the task
requirements appended; **everyone else just calls the skill** and it auto-loads context.

| Command | Who | Behavior |
|---|---|---|
| `/team-leader <requirements>` | leader | Design 1 leader + 1 proxy + N members; emit launch prompts; brief boss; **wait for boss "Ok"**; relay; terminate only when leader says done. |
| `/proxy` | proxy (hub) | Auto-load context from `agent-shared-context` memory + radio bus; split leader directive into per-member sub-prompts; synthesize member results; relay; honor boss "Ok" gate. |
| `/member` | member (worker) | Auto-load context (memory + bus); execute assigned share with evidence; post to `worklog`; report; honor boss "Ok" gate. |
| `/cross-session` | any | Use `tak2-08/memory` as the inter-session coordination bus (`sessions/<task-id>/`). |
| `/debate <topic>` | proxy (moderator) | Stance-based debate: 수용/부정/긍정/조건부부정/공격/방어; synthesize to `proxy-debate-<n>.md`. |
| `/memory-dream` | any | Consolidate daily notes → `MEMORY.md` (+ compaction role). |

**Key rule (from the user's spec):** 팀장은 업무만 만들고 팀원/대리 세션이 답신할 때까지
대기한다. 팀장은 업무 생성 후 사장에게 프록시/팀원 세션 생성을 요청하고, 다 만들어지면
"Ok"를 보낼 것을 안내한다. 사장 "Ok" → 대기(답신), 답신 → 각자 처리 → 사장 "Ok" 감독 →
다시 대기. **팀장이 "일 끝났다" 선언 시에만 종료.**

### Single-session variant (no separate sessions)

If the boss says "그냥 협력하자" (not session collaboration) and your model supports
parallel sub-agents (the `task` tool): **do NOT spawn multiple sessions.** Instead, within
this one session, launch `task` sub-agents as your proxy/members (사원/대리) and coordinate
them over the radio bus (`RADIO_ROOT`, auto-injected into sub-agents). The same relay /
"Ok" gate / terminate rules apply; the only difference is the boss's "Ok" is typed here.

### Opencode single-session variant — Meeting Room only (NEW)

For **opencode specifically**, use the **Radio-Assembler** agent (`.opencode/agents/radio-assembler.md`)
which spawns `radio-proxy` + `radio-member` sub-agents via `task` and coordinates **entirely
through `agent-shared-context` meeting rooms** — **no radio bus at all**.

Key differences from radio-based single-session:
- **Zero radio usage** after bootstrap — all coordination via `agent-meeting.mjs`
- Meeting types map to collaboration phases: `planning` → `discussion`/`rebuttal` → `decision` → `review` → `retrospective`
- Speech kinds replace radio prefixes: `statement`/`objection`/`action-item`/`decision`/`summary`/`agreement`
- Supervision gate = boss `agreement` speech in meeting room (not typed "Ok")
- Minutes auto-saved as `agent-context` entries (type: `meeting`) → searchable via `agent-search-lite.mjs`
- Run via slash command: `/radio-assembler <goal>` (see `.opencode/commands/radio-assembler.md`)

This is the **recommended opencode workflow** for multi-agent tasks.

### Multi-session variant

Separate terminals/processes each get a copy of the launch prompt from `/team-leader`.
Export the **same `RADIO_ROOT`**; distinct agent IDs. The watcher loop (below) + five-phase
rules run in each agent's context. Cross-session state lives in `tak2-08/memory`
(`/cross-session`).

## Running it with real teams

- **Multiple agent processes** (e.g. several `claude -p` / `opencode run` sessions, tmux
  panes): give each a copy of this folder, export the same `RADIO_ROOT`, distinct agent
  IDs, and put the watcher loop + five-phase rules in each agent's system prompt /
  CLAUDE.md. See `prompts/peer-CLAUDE.md.template`.
- **Single orchestrator with subagents**: launch explorers/workers in parallel; have each
  worker append findings to the shared `worklog` thread as it goes; poll the thread at
  your own step boundaries (your tool-call boundaries play the role of the watcher).
- **Fidelity ladder** (from the paper — use it to decide how much process you need):
  B0 solo → L1 division of labor only → L2 + negotiated plan but blocking receive →
  L3 full passive awareness. Most of L3's win comes from mid-execution correction; skip
  the radio entirely for tasks too small to have a "middle".

## Files

```
scripts/radio.sh                         CLI wrapper (sh)
scripts/radio_main.py                    implementation (python3 stdlib only)
prompts/team-leader-CLAUDE.md.template   leader session system prompt
prompts/proxy-CLAUDE.md.template         proxy (hub) session system prompt
prompts/member-CLAUDE.md.template        member (worker) session system prompt
prompts/peer-CLAUDE.md.template          generic peer system prompt (single-session fallback)
```

Opencode agents (`.opencode/agents/`):
`radio-assembler.md` · `radio-proxy.md` · `radio-member.md`

Slash commands (opencode, in .opencode/commands/):
`/team-leader <req>` · `/proxy` · `/member` · `/cross-session` · `/debate <topic>` · `/memory-dream` · `/radio-assembler <goal>`

Environment: `RADIO_ROOT` (bus location), `RADIO_POLL_SEC` (watcher poll interval, default 1s).
