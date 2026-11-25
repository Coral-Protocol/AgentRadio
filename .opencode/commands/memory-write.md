---
description: "Write to memory: daily log (append) or curated MEMORY.md — GitHub-backed universal store"
agent: build
---

Write to the universal GitHub-backed memory store (`tak2-08/memory`, shared by all sessions/agents/environments):

- For raw logs/observations: `memory_write` with path="daily" and content="$ARGUMENTS" (or ask for content). This appends to `memory/YYYY-MM-DD.md` and pushes to GitHub.
- For durable facts/preferences/decisions: `memory_write` with path="MEMORY.md" and curated markdown.

Ask user which target if $ARGUMENTS is ambiguous, then call the tool and report the written path.

Note: in non-opencode environments use the portable CLI: `memory write --path daily --content "..."` (see https://github.com/tak2-08/memory).
