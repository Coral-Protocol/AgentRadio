#!/usr/bin/env python3
"""Claude Code PostToolUse hook: deliver new team messages into the agent's context.

Configured in the agent's .claude/settings.local.json (PostToolUse + PostToolUseFailure,
every tool). Claude Code runs it after each tool call; it reads this agent's
coral://state over MCP (Streamable HTTP, stdlib only, no proxy), diffs it against a
cursor file, and prints a hook JSON response whose additionalContext lists the peer
messages that arrived since the last delivery. Claude Code wraps that text in a system
reminder next to the tool result, so the agent sees new messages on its next model
request without polling and without a watcher process (harness-level passive awareness).

usage: inbox_hook.py <instance_dir>                 (hook mode; stdin = hook input JSON)
       inbox_hook.py <instance_dir> --state-file F  (offline test: F is a saved coral://state)

files under <instance_dir>:  url.txt (this agent's MCP URL, written by startup_pb.sh)
                              .inbox/cursor.json .inbox/sid .inbox/lock
log: <instance_dir>/../<agent>-inbox.log, one line per hook call:
     C <unix> <event> <tool> <ms> <new>            a check (new = messages delivered)
     D <unix> <thread> <sender> <msg_unix> <lat_s> <chars> <mentions_me>   one delivered message
     E <unix> <error>                                a failure (nothing delivered)
Output size is capped so the reminder never hits Claude Code's 10,000-char limit;
undelivered messages are kept for the next call.
"""
import datetime
import fcntl
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

MAX_CHARS = 8000          # cap on additionalContext (Claude Code truncates to a file at 10k)
HTTP_TIMEOUT = 5
NO_PROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def ts_key(s):
    """ISO-8601 with up to 9 fraction digits -> (epoch seconds, nanoseconds)."""
    s = s.strip().rstrip("Z")
    base, _, frac = s.partition(".")
    sec = datetime.datetime.fromisoformat(base).replace(tzinfo=datetime.timezone.utc).timestamp()
    ns = int((frac + "000000000")[:9]) if frac else 0
    return (int(sec), ns)


def ts_float(s):
    k = ts_key(s)
    return k[0] + k[1] / 1e9


def http_post(url, body, sid=None):
    headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    if sid:
        headers["Mcp-Session-Id"] = sid
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method="POST")
    with NO_PROXY.open(req, timeout=HTTP_TIMEOUT) as r:
        return r.headers, r.read().decode("utf-8", "replace")


def rpc_extract(text):
    last = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("data: "):
            line = line[6:]
        if line.startswith("{"):
            last = line
    return json.loads(last) if last else None


def mcp_init(url):
    headers, _ = http_post(url, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                 "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                                            "clientInfo": {"name": "inbox-hook", "version": "1"}}})
    sid = headers.get("Mcp-Session-Id") or headers.get("mcp-session-id")
    if not sid:
        raise RuntimeError("no Mcp-Session-Id from initialize")
    http_post(url, {"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    return sid


def read_state(url, inbox_dir):
    sid_file = os.path.join(inbox_dir, "sid")
    sid = open(sid_file).read().strip() if os.path.exists(sid_file) else ""
    for attempt in (1, 2):
        if not sid:
            sid = mcp_init(url)
            with open(sid_file, "w") as f:
                f.write(sid)
        try:
            _, text = http_post(url, {"jsonrpc": "2.0", "id": 3, "method": "resources/read",
                                      "params": {"uri": "coral://state"}}, sid)
            resp = rpc_extract(text)
            if resp and "result" in resp:
                return resp["result"]["contents"][0]["text"]
            raise RuntimeError(f"rpc error: {str(resp)[:200]}")
        except (urllib.error.HTTPError, RuntimeError):
            if attempt == 2:
                raise
            sid = ""  # stale session: re-initialize once


def parse_state(text):
    me = None
    m = re.search(r"You are an agent named (\S+?)\.", text)
    if m:
        me = m.group(1)
    blocks = re.findall(r"```json\s*(.*?)```", text, flags=re.S)
    threads = []
    for b in blocks:
        try:
            d = json.loads(b)
        except Exception:
            continue
        if isinstance(d, list) and d and isinstance(d[0], dict) and "threadId" in d[0]:
            threads = d
    return me, threads


def fmt_time(ts):
    return datetime.datetime.utcfromtimestamp(ts_float(ts)).strftime("%H:%M:%S")


def main():
    t0 = time.time()
    inst = os.path.abspath(sys.argv[1])
    state_file = None
    if "--state-file" in sys.argv:
        state_file = sys.argv[sys.argv.index("--state-file") + 1]
    inbox_dir = os.path.join(inst, ".inbox")
    os.makedirs(inbox_dir, exist_ok=True)
    agent = os.path.basename(inst)
    log_path = os.path.join(os.path.dirname(inst), f"{agent}-inbox.log")

    hook_in = {}
    if not sys.stdin.isatty():
        try:
            hook_in = json.loads(sys.stdin.read() or "{}")
        except Exception:
            hook_in = {}
    event = hook_in.get("hook_event_name") or "PostToolUse"
    tool = hook_in.get("tool_name") or "-"

    def log(line):
        with open(log_path, "a") as f:
            f.write(line + "\n")

    lock = open(os.path.join(inbox_dir, "lock"), "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        if state_file:
            text = open(state_file).read()
        else:
            url = open(os.path.join(inst, "url.txt")).read().strip()
            text = read_state(url, inbox_dir)
        me, threads = parse_state(text)
        me = me or os.environ.get("CORAL_AGENT_ID") or agent

        cur_path = os.path.join(inbox_dir, "cursor.json")
        cursor = {}
        if os.path.exists(cur_path):
            try:
                cursor = json.load(open(cur_path))
            except Exception:
                cursor = {}

        pending = []  # (key, thread, msg)
        for th in threads:
            tid = th.get("threadId")
            last = cursor.get(tid)
            last_key = ts_key(last) if last else (0, 0)
            for msg in th.get("messages", []):
                k = ts_key(msg.get("messageTimestamp", "1970-01-01T00:00:00Z"))
                if k > last_key:
                    pending.append((k, th, msg))
        pending.sort(key=lambda x: x[0])

        delivered = []
        parts = []
        total = 0
        now = time.time()
        for k, th, msg in pending:
            sender = msg.get("sendingAgentName")
            if sender == me:
                delivered.append((k, th, msg, False))   # own message: advance cursor silently
                continue
            mentions = msg.get("mentionAgentNames") or []
            body = msg.get("messageText") or ""
            head = (f"--- #{len(parts)+1} thread '{th.get('threadName')}' (id {th.get('threadId')}) | "
                    f"{fmt_time(msg.get('messageTimestamp'))} UTC | from {sender}"
                    + (" -> " + " ".join("@" + x for x in mentions) if mentions else " (no mentions)")
                    + (" | mentions YOU" if me in mentions else ""))
            piece = head + "\n" + body
            if total + len(piece) > MAX_CHARS:
                if not parts:  # a single oversized message: truncate it rather than stall
                    piece = piece[: MAX_CHARS - 200] + "\n[... truncated; full text: bash scripts/read_resource.sh]"
                else:
                    break
            parts.append(piece)
            total += len(piece) + 1
            delivered.append((k, th, msg, True))

        # advance the cursor only over what was delivered (own messages included)
        for k, th, msg, _ in delivered:
            tid = th.get("threadId")
            if not cursor.get(tid) or k > ts_key(cursor[tid]):
                cursor[tid] = msg.get("messageTimestamp")
        with open(cur_path + ".tmp", "w") as f:
            json.dump(cursor, f)
        os.replace(cur_path + ".tmp", cur_path)

        remaining = sum(1 for k, th, msg in pending if k > max((d[0] for d in delivered), default=(0, 0))
                        and msg.get("sendingAgentName") != me)
        ms = int((time.time() - t0) * 1000)
        shown = [d for d in delivered if d[3]]
        log(f"C {now:.3f} {event} {tool} {ms} {len(shown)}")
        for k, th, msg, _ in shown:
            mt = ts_float(msg["messageTimestamp"])
            log(f"D {now:.3f} {th.get('threadName')} {msg.get('sendingAgentName')} {mt:.3f} {now-mt:.1f} "
                f"{len(msg.get('messageText') or '')} {1 if me in (msg.get('mentionAgentNames') or []) else 0}")
        if shown:
            header = (f"[TEAM INBOX] {len(shown)} new message(s) from your peers, delivered by the harness after "
                      f"this tool call. Handle them as your CLAUDE.md says (URGENT or anything that changes your "
                      f"current work: now; otherwise after the piece you are in). Reply with "
                      f"bash scripts/send_message.sh <threadId> \"<text>\" [mentions]."
                      + (f" {remaining} more waiting; they arrive after your next tool call." if remaining else ""))
            ctx = header + "\n" + "\n".join(parts)
            print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": ctx}}))
    except Exception as e:  # never block the tool result; log and stay silent
        try:
            log(f"E {time.time():.3f} {type(e).__name__}: {str(e)[:200]}")
        except Exception:
            pass
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN)


if __name__ == "__main__":
    main()
