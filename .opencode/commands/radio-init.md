---
description: "Init AgentRadio bus for this worktree (idempotent)"
agent: build
---

Initialize the AgentRadio radio bus for this worktree.

Steps:
1. Run `radio_init` tool to ensure `RADIO_ROOT` threads dir exists.
2. Run `radio_threads` to show current threads.
3. Report `RADIO_ROOT` path and that all sessions/subagents in this worktree now share it passively.
