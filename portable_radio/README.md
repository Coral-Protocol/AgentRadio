# portable_radio — AgentRadio without the JAR

A dependency-free, file-backed implementation of the [AgentRadio](https://github.com/Coral-Protocol/AgentRadio)
communication layer (paper: [arXiv:2607.28430](https://arxiv.org/abs/2607.28430)).

Upstream runs the Coral message server (`coral-server.jar`, JDK 24) inside a Harbor/Modal
container. That is the right tool for benchmark reproduction, but it blocks adoption in
places where Docker/Modal/JDK are unavailable — a laptop tmux session, a CI runner, an
editor-embedded agent host, an air-gapped box. `portable_radio` keeps the protocol and
drops the infrastructure:

| Upstream | portable_radio |
|---|---|
| Coral message server (JVM) | append-only JSONL directory (`$RADIO_ROOT`) |
| `create_thread` / `send_message` / `wait_for_mention` MCP tools | the same three verbs via one shell CLI (`scripts/radio.sh`) |
| MCP-over-HTTP with baked-in per-agent URL wrappers | no server at all; agents share a filesystem path |
| long-poll on the server | 1 s polling loop (`RADIO_POLL_SEC`), watcher still run as a background task |
| self-contained watcher output (mention + `coral://state` dump) | identical contract: new message + full dump of every thread |

## Quick start

```bash
export RADIO_ROOT=/tmp/demo-radio
scripts/radio.sh init

# terminal A (or agent process A) — start a watcher in the background:
scripts/radio.sh wait agent-1 --max-wait 300 &

# terminal B — this wakes agent-1's watcher immediately:
scripts/radio.sh send worklog agent-2 "URGENT: assumption in plan step 3 is wrong" --mentions agent-1
```

Run `scripts/radio.sh wait <me>` as a **background task** and keep exactly one running;
that single rule is what turns blocking receive (L2) into passive awareness (L3).

## What's included

```
SKILL.md                       protocol guide (frontmatter works as an opencode/Claude-Code skill)
scripts/radio.sh               CLI wrapper
scripts/radio_main.py          implementation (python3 stdlib only)
prompts/peer-CLAUDE.md.template  per-agent system prompt for the five-phase protocol
```

## Fidelity notes

- Message durability: lines are appended with O_APPEND semantics; concurrent sends from
  many processes are safe for realistic message sizes.
- `wait` breaks on a mention of the caller OR any message past its baseline, mirroring
  upstream `wait_for_mention.sh`, and prints a full state dump so the caller never needs
  a separate read.
- No ACLs/auth: everyone who can read `$RADIO_ROOT` can read everything, like the
  upstream shared namespace. Use a private directory.
- Threads are created implicitly on first send, matching upstream `create_thread` +
  `send_message` convenience.

Apache-2.0, same as the rest of the repository.
