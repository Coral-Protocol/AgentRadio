---
description: "Read an exact excerpt from memory (MEMORY.md or daily notes) — GitHub-backed universal store"
agent: build
---

Read an exact excerpt from the universal GitHub-backed memory store (`tak2-08/memory`):

1. Call `memory_get` with path="$ARGUMENTS" (e.g. `MEMORY.md` or `memory/2026-08-26.md`). If $ARGUMENTS is empty or ambiguous, ask which file/section.
2. Optionally pass `from` (start line) and `lines` (count) to narrow.
3. Report the excerpt with its Source: path#line citation.

Non-opencode fallback: `memory get <path> [from] [lines]` (portable CLI from https://github.com/tak2-08/memory).
