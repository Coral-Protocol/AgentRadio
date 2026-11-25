---
description: "Show full AgentRadio bus state (threads + messages)"
agent: build
---

Show current AgentRadio bus state:
1. Call `radio_threads` to list threads.
2. Call `radio_read` (limit 100) to dump all messages chronologically.
3. Summarize: bus location, total messages, threads, and passive-awareness status (auto-injected).
