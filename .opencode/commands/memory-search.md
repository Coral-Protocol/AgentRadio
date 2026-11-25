---
description: "Search long-term memory (MEMORY.md + daily notes) before answering about prior work — GitHub-backed universal store"
agent: build
---

Before answering about prior work, decisions, dates, people, preferences, or todos: run memory_search (this store is shared across ALL sessions/agents/environments via the GitHub repo `tak2-08/memory`).

Steps:
1. Call `memory_search` with query="$ARGUMENTS" (if $ARGUMENTS empty, ask user for query).
2. If hits found, call `memory_get` for top 1-2 hits to pull exact lines with citations.
3. Answer from the snippets, include Source: path#line citations.
4. If no hits or low confidence, say you checked and found nothing.

Non-opencode fallback: `memory search "query"` (portable CLI from https://github.com/tak2-08/memory).
