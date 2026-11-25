#!/usr/bin/env python3
"""radio_main.py — implementation behind radio.sh.

A thread is one append-only JSONL file: threads/<name>.jsonl. Each line:
    {"id": "...", "ts": <ns>, "from": "agent-1", "mentions": ["agent-2"], "content": "..."}

`wait` reproduces the upstream watcher contract: it breaks on a new mention of
the caller OR on any message appended after the baseline count, and its output
is SELF-CONTAINED — the new messages plus a full dump of every thread — so the
caller never needs a separate read to reconstruct context.
"""

import json
import os
import sys
import time

VALID_THREAD = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")


def die(msg, code=2):
    print("ERROR: %s" % msg, file=sys.stderr)
    sys.exit(code)


def parse_argv(argv):
    args = []
    kwargs = {}
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok == "--root":
            kwargs["root"] = argv[i + 1]
            i += 2
        elif tok == "--mentions":
            kwargs["mentions"] = [m for m in argv[i + 1].split(",") if m]
            i += 2
        elif tok == "--max-wait":
            kwargs["max_wait"] = float(argv[i + 1])
            i += 2
        elif tok == "--max-rounds":
            kwargs["max_rounds"] = int(argv[i + 1])
            i += 2
        elif tok.startswith("--"):
            die("unknown option %s" % tok)
        else:
            args.append(tok)
            i += 1
    return args, kwargs


def get_root(kwargs):
    return kwargs.get("root") or os.environ.get("RADIO_ROOT") or ".radio"


def thread_file(root_dir, name):
    if not name or set(name) - VALID_THREAD:
        die("invalid thread name: %r" % name)
    return os.path.join(root_dir, "threads", name + ".jsonl")


def load_all(root_dir):
    """Return every message across all threads, in global chronological order."""
    tdir = os.path.join(root_dir, "threads")
    msgs = []
    if not os.path.isdir(tdir):
        return msgs
    for fname in sorted(os.listdir(tdir)):
        if not fname.endswith(".jsonl"):
            continue
        with open(os.path.join(tdir, fname), encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    m = json.loads(line)
                except ValueError:
                    continue
                m["_thread"] = fname[:-6]
                msgs.append(m)
    msgs.sort(key=lambda m: (m.get("ts", 0), m.get("id", "")))
    return msgs


def fmt_message(m):
    mentions = ",".join("@%s" % x for x in m.get("mentions", []))
    head = "[%s] %s" % (m["_thread"], m.get("from", "?"))
    if mentions:
        head += " -> %s" % mentions
    ts = m.get("ts", 0) / 1e9
    stamp = time.strftime("%H:%M:%S", time.localtime(ts))
    return "%s (%s)\n  %s" % (head, stamp, m.get("content", "").replace("\n", "\n  "))


def fmt_state(msgs):
    if not msgs:
        return "(no messages yet)"
    out = []
    current = object()
    for m in msgs:
        if m["_thread"] != current:
            out.append("## thread: %s" % m["_thread"])
            current = m["_thread"]
        out.append(fmt_message(m))
    return "\n".join(out)


def cmd_init(args, kwargs):
    root_dir = get_root(kwargs)
    os.makedirs(os.path.join(root_dir, "threads"), exist_ok=True)
    meta = {"created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "protocol": "agent-radio/passive"}
    with open(os.path.join(root_dir, "meta.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)
    print("radio ready at %s" % root_dir)


def cmd_send(args, kwargs):
    if len(args) < 3:
        die("usage: send <thread> <from> <content> [--mentions csv]")
    name, sender, content = args[0], args[1], args[2]
    root = get_root(kwargs)
    # Ensure threads directory exists
    threads_dir = os.path.join(root, "threads")
    os.makedirs(threads_dir, exist_ok=True)
    path = thread_file(root, name)
    raw_mentions = kwargs.get("mentions", [])
    mentions = []
    if raw_mentions:
        for m in raw_mentions.split(","):
            m = m.strip()
            if not m:
                continue
            if not m.startswith("@") or not m[1:].replace("-", "").replace("_", "").isalnum():
                die(f"invalid mention: {m}")
            mentions.append(m)
    msg = {
        "id": "m-%d-%d" % (time.time_ns(), os.getpid()),
        "ts": time.time_ns(),
        "from": sender,
        "mentions": mentions,
        "content": content,
    }
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(msg) + "\n")
    print(json.dumps({"sent": True, "thread": name, "id": msg["id"]}))


def cmd_wait(args, kwargs):
    if not args:
        die("usage: wait <me> [--max-wait SEC] [--max-rounds N]")
    me = args[0]
    max_wait = kwargs.get("max_wait", 60.0)
    max_rounds = kwargs.get("max_rounds", 1)
    poll = float(os.environ.get("RADIO_POLL_SEC", "1.0"))

    baseline = len(load_all(get_root(kwargs)))
    print(">> baseline: %d message(s) currently visible in the session" % baseline, file=sys.stderr)

    round_no = 0
    while True:
        round_no += 1
        deadline = time.monotonic() + max_wait
        while time.monotonic() < deadline:
            msgs = load_all(get_root(kwargs))
            fresh = msgs[baseline:]
            for m in fresh:
                mentioned = me in m.get("mentions", []) or ("@%s" % me) in m.get("content", "")
                if mentioned:
                    _report(round_no, "MENTION RECEIVED", m, msgs)
                    return 0
            if fresh:  # any new traffic also breaks the wait, like upstream
                _report(round_no, "NEW MESSAGE(S) FOUND", fresh[0], msgs)
                return 0
            time.sleep(poll)
        print("[round %d] wait timed out (%ss)" % (round_no, max_wait), file=sys.stderr)
        if max_rounds > 0 and round_no >= max_rounds:
            msgs = load_all(get_root(kwargs))
            print("", file=sys.stderr)
            print("=== CURRENT STATE (nothing new after baseline=%d) ===" % baseline)
            print(fmt_state(msgs))
            return 1


def _report(round_no, why, first, all_msgs):
    print("", file=sys.stderr)
    print("=== [round %d] %s ===" % (round_no, why))
    print(fmt_message(first))
    print("")
    print("=== CURRENT STATE (full, so this output is self-contained) ===")
    print(fmt_state(all_msgs))


def cmd_read(args, kwargs):
    print(fmt_state(load_all(get_root(kwargs))))


def cmd_threads(args, kwargs):
    tdir = os.path.join(get_root(kwargs), "threads")
    if os.path.isdir(tdir):
        for fname in sorted(os.listdir(tdir)):
            if fname.endswith(".jsonl"):
                print(fname[:-6])


def main():
    argv = sys.argv[1:]
    if not argv:
        die("usage: radio.sh {init|send|wait|read|threads} ...")
    cmd, rest = argv[0], argv[1:]
    args, kwargs = parse_argv(rest)
    table = {
        "init": cmd_init,
        "send": cmd_send,
        "wait": cmd_wait,
        "read": cmd_read,
        "threads": cmd_threads,
    }
    if cmd not in table:
        die("unknown command %r" % cmd)
    sys.exit(table[cmd](args, kwargs))


if __name__ == "__main__":
    main()
