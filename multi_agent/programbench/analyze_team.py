#!/usr/bin/env python3
"""Process metrics for one ProgramBench team run (L25P, L3 or L3H).

usage: python3 analyze_team.py <trial_dir> [--windows 5-10,30-35,50-54]

Reads from <trial_dir>/agent/:
  coral-state/*.json          server session dump: every message with sender, mentions, time
  agent-N-claude-code.txt     stream-json log, each line prefixed with a unix timestamp
  run.log                     runner clock (start time, snapshots)
  git-log.txt                 "HH:MM:SS author subject" per commit
  agent-N-inbox.log           (l3h) hook checks and deliveries with send->delivery latency
Prints: message counts per agent and per kind, a per-minute message timeline, messages
outside the allowed windows (fixed-window condition), tool calls / edits / watcher and
bell launches per agent, commits per author, and FAIL -> fix latencies.
"""
import glob, json, re, sys, collections, datetime
from pathlib import Path

KINDS = ["BRIEF", "SPLIT", "CLAIM", "DONE", "FACT", "FAIL", "FIXED", "PASS", "REQUEST", "URGENT", "FYI", "STATUS", "ACK"]

def parse_ts(s):
    s = s.rstrip("Z"); s = s[:26]
    return datetime.datetime.fromisoformat(s).replace(tzinfo=datetime.timezone.utc).timestamp()

def main():
    trial = Path(sys.argv[1]); agent_dir = trial / "agent"
    windows = []
    if "--windows" in sys.argv:
        for w in sys.argv[sys.argv.index("--windows") + 1].split(","):
            a, b = w.split("-"); windows.append((int(a), int(b)))
    # team clock
    start = None
    for line in (agent_dir / "run.log").read_text().splitlines():
        if "[runner] start" in line:
            start = parse_ts(line.split()[0]); break
    # messages
    msgs = []
    for f in glob.glob(str(agent_dir / "coral-state" / "*.json")):
        d = json.load(open(f))
        for th in d.get("threads", []):
            for m in th.get("messages", []):
                msgs.append(dict(t=parse_ts(m["timestamp"]), sender=m.get("senderName"), mentions=m.get("mentionNames") or [],
                                 text=m.get("text") or "", thread=th.get("name")))
    msgs.sort(key=lambda m: m["t"])
    if start is None and msgs: start = msgs[0]["t"]
    print(f"== {trial.name}: {len(msgs)} messages, team clock start {datetime.datetime.utcfromtimestamp(start):%H:%M:%S}Z")
    per_agent = collections.defaultdict(collections.Counter)
    outside = []
    for m in msgs:
        minute = (m["t"] - start) / 60
        kind = next((k for k in KINDS if m["text"].lstrip().upper().startswith(k)), "other")
        per_agent[m["sender"]][kind] += 1
        per_agent[m["sender"]]["total"] += 1
        if windows and not any(a <= minute <= b + 0.5 for a, b in windows):
            outside.append((minute, m["sender"], m["text"][:60]))
    print("\n-- messages per agent and kind")
    kinds = [k for k in KINDS if any(c[k] for c in per_agent.values())]
    print(f"{'agent':8} {'total':>5} " + " ".join(f"{k:>7}" for k in kinds))
    for a in sorted(per_agent):
        print(f"{a:8} {per_agent[a]['total']:5d} " + " ".join(f"{per_agent[a][k]:7d}" for k in kinds))
    print("\n-- timeline (minute: sender kind first words)")
    for m in msgs:
        minute = (m["t"] - start) / 60
        print(f"{minute:5.1f}  {m['sender']:8} {m['text'][:90].replace(chr(10),' ')}")
    if windows:
        print(f"\n-- messages OUTSIDE windows {windows}: {len(outside)}")
        for mi, s, t in outside: print(f"{mi:5.1f} {s:8} {t}")
    # FAIL -> FIXED/PASS latency (by mentioned owner)
    fails = [(m["t"], m["sender"], m["mentions"], m["text"]) for m in msgs if m["text"].lstrip().upper().startswith(("FAIL", "URGENT FAIL"))]
    fixes = [(m["t"], m["sender"], m["text"]) for m in msgs if m["text"].lstrip().upper().startswith(("FIXED", "PASS", "DONE"))]
    if fails:
        print("\n-- FAIL reports and the owner's next FIXED/PASS/DONE")
        for t, s, men, txt in fails:
            owner = men[0] if men else None
            later = [ft for ft, fs, _ in fixes if fs == owner and ft > t]
            lat = f"{(later[0]-t)/60:5.1f} min" if later else "  none"
            print(f"{(t-start)/60:5.1f}  {s:8} -> {owner}: {lat}  {txt[:60]}")
    # agent logs
    print("\n-- per-agent activity from stream-json logs")
    print(f"{'agent':8} {'turns':>5} {'tools':>5} {'edits':>5} {'bash':>5} {'watch':>5} {'bells':>5} {'wait_fg':>7} {'send':>5} {'reads':>5} {'wait_out':>8} {'read_out':>8} {'relaunch':>8}")
    print("   (reads = coral://state reads; *_out = blocking waits / state reads outside the --windows, i.e. in working phases)")
    for f in sorted(glob.glob(str(agent_dir / "agent-*-claude-code.txt"))):
        a = re.search(r"(agent-\d)", f).group(1)
        c = collections.Counter()
        for line in open(f, errors="replace"):
            parts = line.split(" ", 1)
            body = parts[1] if len(parts) == 2 and re.match(r"^\d+\.\d+$", parts[0]) else line
            minute = (float(parts[0]) - start) / 60 if len(parts) == 2 and re.match(r"^\d+\.\d+$", parts[0]) and start else None
            in_win = (not windows) or minute is None or any(a <= minute <= b + 0.5 for a, b in windows)
            if body.startswith(">>> [resume-guard] claude exited"): c["relaunch"] += 1
            if not body.startswith("{"): continue
            try: d = json.loads(body)
            except Exception: continue
            if d.get("type") != "assistant": continue
            c["turns"] += 1
            for b in d.get("message", {}).get("content", []):
                if b.get("type") != "tool_use": continue
                c["tools"] += 1
                name = b.get("name"); inp = b.get("input", {})
                if name in ("Edit", "Write", "MultiEdit"): c["edits"] += 1
                if name == "Bash":
                    c["bash"] += 1
                    cmd = inp.get("command", "")
                    bg = inp.get("run_in_background")
                    if "wait_for_mention.sh" in cmd: c["watch" if bg else "wait_fg"] += 1
                    if "next_bell.sh" in cmd: c["bells"] += 1
                    if "send_message.sh" in cmd: c["send"] += 1
                if name and name.startswith("mcp__coral__"):
                    if "wait_for_mention" in name:
                        c["wait_fg"] += 1
                        if not in_win: c["wait_out"] += 1
                    if "send_message" in name: c["send"] += 1
                if (name == "ReadMcpResourceTool" and "coral://state" in str(inp.get("uri", ""))) or (name == "Bash" and "read_resource.sh" in inp.get("command", "")):
                    c["reads"] += 1
                    if not in_win: c["read_out"] += 1
        print(f"{a:8} {c['turns']:5d} {c['tools']:5d} {c['edits']:5d} {c['bash']:5d} {c['watch']:5d} {c['bells']:5d} {c['wait_fg']:7d} {c['send']:5d} {c['reads']:5d} {c['wait_out']:8d} {c['read_out']:8d} {c['relaunch']:8d}")
    # harness inbox (hook-delivered condition): one log per agent written by inbox_hook.py
    inbox = sorted(glob.glob(str(agent_dir / "agent-*-inbox.log")))
    if inbox:
        print("\n-- harness inbox (hook): checks = hook calls, deliv = calls that delivered, msgs = peer messages delivered,")
        print("   latency = seconds from a peer's send to its delivery into this agent's context, hook_ms = mean hook run time")
        print(f"{'agent':8} {'checks':>6} {'deliv':>5} {'msgs':>5} {'lat_med':>8} {'lat_p90':>8} {'lat_max':>8} {'hook_ms':>7} {'errors':>6}")
        for f in inbox:
            a = re.search(r"(agent-\d)", f).group(1)
            checks = deliv = errs = 0; lats = []; ms = []
            for line in open(f, errors="replace"):
                p = line.split()
                if not p: continue
                if p[0] == "C" and len(p) >= 6:
                    checks += 1; ms.append(int(p[4])); deliv += 1 if int(p[5]) > 0 else 0
                elif p[0] == "D" and len(p) >= 6:
                    lats.append(float(p[5]))
                elif p[0] == "E":
                    errs += 1
            lats.sort()
            q = lambda v: lats[min(len(lats) - 1, int(v * len(lats)))] if lats else 0.0
            print(f"{a:8} {checks:6d} {deliv:5d} {len(lats):5d} {q(0.5):8.1f} {q(0.9):8.1f} {(lats[-1] if lats else 0.0):8.1f} {(sum(ms)/len(ms) if ms else 0):7.0f} {errs:6d}")
    # commits
    gl = agent_dir / "git-log.txt"
    if gl.exists():
        authors = collections.Counter(l.split()[1] for l in gl.read_text().splitlines() if len(l.split()) > 2)
        print("\n-- commits per author:", dict(authors))

main()
