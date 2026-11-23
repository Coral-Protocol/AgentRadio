#!/bin/bash
# DeepSWE Multi-Agent startup script — L2.5 (L2 phases and gates kept; the WORKING phases
# use the L3 share-as-you-go rules, but nothing is pushed: agents receive by reading
# coral://state themselves). Launched by the message server for each agent instance.
#
# Design: four agents investigate (Phases 1-4), ONE agent (agent-1) implements, the
# team reviews the diff, agent-1 commits (Phase 5). agent-2/3/4 never modify the repo.
# DISCUSSION phases (Phase 2, Phase 4, the Phase 5 review) are exactly the L2 ones: MCP
# tools and the foreground coral_wait_for_mention loop. WORKING phases (Phase 3, and
# Phase 5 while agent-1 implements) take the L3 WORKLOG sharing rules, with self-read
# receive instead of a watcher: coral_wait_for_mention is forbidden there, agents read
# the coral://state resource at natural boundaries. Everything else is the L2 text.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTBED_DIR="$(dirname "$SCRIPT_DIR")"
INSTANCE_DIR="$SCRIPT_DIR/instances/$CORAL_SESSION_ID/$CORAL_AGENT_ID"
mkdir -p "$INSTANCE_DIR"

CLAUDE_SETTINGS_DIR="$INSTANCE_DIR/.claude"
mkdir -p "$CLAUDE_SETTINGS_DIR"

echo "=== DeepSWE Agent (L2.5: blocking in discussion phases, share-as-you-go working phases, self-read receive) ==="
echo "Agent ID:       $CORAL_AGENT_ID"
echo "Session ID:     $CORAL_SESSION_ID"
echo "Connection URL: $CORAL_CONNECTION_URL"
echo "Instance dir:   $INSTANCE_DIR"

# Container paths
REPO_DIR="${CORAL_REPO_DIR:-/app}"
INSTRUCTION_PATH="${CORAL_INSTRUCTION_PATH:-/tmp/coral-workspace/instruction.md}"
BRIEF_PATH="${CORAL_BRIEF_PATH:-/tmp/coral-workspace/brief.md}"
SCRATCH_DIR="/tmp/scratch-$CORAL_AGENT_ID"
mkdir -p "$SCRATCH_DIR"

# Write .mcp.json for MCP server discovery
cat > "$INSTANCE_DIR/.mcp.json" << EOF
{
  "mcpServers": {
    "coral": {
      "type": "http",
      "url": "$CORAL_CONNECTION_URL",
      "timeout": 1200000
    }
  }
}
EOF

# Auto-trust the MCP server
cat > "$CLAUDE_SETTINGS_DIR/settings.local.json" << EOF
{
  "permissions": {
    "allow": [
      "mcp__coral"
    ]
  },
  "enabledMcpjsonServers": [
    "coral"
  ],
  "enableAllProjectMcpServers": true
}
EOF

IS_IMPLEMENTER="false"
if [ "$CORAL_AGENT_ID" = "agent-1" ]; then
  IS_IMPLEMENTER="true"
fi

# Write CLAUDE.md (system prompt - auto-loaded by Claude Code)
cat > "$INSTANCE_DIR/CLAUDE.md" << CLAUDE_EOF
# DeepSWE Multi-Agent Team

You are $CORAL_AGENT_ID, one of 4 agents collaborating to implement a feature request
in a real repository. Your peers: agent-1, agent-2, agent-3, agent-4.
You communicate via the MCP tools. In DISCUSSION phases you wait for mentions; in
WORKING phases nothing is pushed to you and you read coral://state yourself (see below).

The task instruction is at: $INSTRUCTION_PATH
The target repository is at: $REPO_DIR
The shared implementation brief will be at: $BRIEF_PATH (written by agent-1 in Phase 5)
Your private scratch directory is: $SCRATCH_DIR

## How this task is graded

The grader takes the final commit of the branch that agent-1 creates in $REPO_DIR and
runs HIDDEN tests: new tests for the requested feature (fail-to-pass) and the
repository's existing tests (pass-to-pass). The task passes only if ALL of them pass.
Nobody on the team can see the hidden tests, so the team must reconstruct them from
the instruction: every sentence of the instruction is a potential test, including
defaults, error cases, and edge cases it mentions in passing.

## Roles

- agent-1: IMPLEMENTER and chair. The ONLY agent that modifies, creates, deletes, or
  commits files under $REPO_DIR. Creates the threads and writes the brief.
- agent-2, agent-3, agent-4: INVESTIGATORS and REVIEWERS. You investigate, report,
  and review. You NEVER modify, create, or delete tracked files under $REPO_DIR, and
  you never run git commands that change state (checkout, commit, stash, reset).
  Running the existing build and test commands is fine. Anything you want to write
  goes to $SCRATCH_DIR.

## Communication Loop (CRITICAL — DISCUSSION phases: Phase 2, Phase 4, the Phase 5 review)

Follow this exact loop every time you wait for messages in a DISCUSSION phase:

1. Call \`coral_wait_for_mention\`
2. After it returns (whether with a message or a timeout), ALWAYS read \`coral://state\` resource to check for any messages you may have missed
3. If you find unread messages in the state that you haven't processed yet, handle them
4. Go back to step 1

This is critical because messages can arrive while you are not waiting, and \`coral_wait_for_mention\` only catches messages that arrive DURING the wait. The \`coral://state\` resource records ALL messages in threads you participate in.

## Working Phases (Phase 3, and Phase 5 while agent-1 implements): share as you go, self-read receive

In a WORKING phase you do NOT call \`coral_wait_for_mention\` — it blocks you — and nothing
is pushed to you: there is no watcher and no hook. Instead:
- SEND as you go: post notes to the shared WORKLOG thread (created by agent-1 at the end
  of Phase 2) the moment you have them (see Phase 3). Sending is fire-and-forget: after
  \`coral_send_message\` returns, continue your work; never stop working to wait for a reply.
- RECEIVE by reading: to learn what your peers posted, read the \`coral://state\` resource
  yourself. It is a full dump of every thread you are in, so work out what is new since
  you last read it and handle it. Read it at natural boundaries — when you finish a
  sub-investigation or a checklist item, before you switch to a new file or track, after
  you post something that needs an answer — and never spin on it.
- Prefix convention so receivers can triage without stopping their work:
  - "FYI:"    — no reply needed; receivers just take note and continue.
  - "URGENT:" — the receiver's current work may be affected (e.g. an assumption they
    rely on looks wrong); handle before starting the next piece of work.
  - No prefix — normal note, reply when you reach a natural break.
- Handling what you read: URGENT, or it changes what you should be doing — deal with it
  now, then resume. Otherwise finish the piece of work you are in, then respond. Never
  silently drop a message; if you defer one, note it down and come back to it before
  moving to the next phase.

## Communication Rules

- In a DISCUSSION phase, after EVERY message you send via \`coral_send_message\`, you MUST immediately enter the Communication Loop above. In a WORKING phase, sending is fire-and-forget (see above).
- Do NOT wait for human input. You are fully autonomous.
- Do NOT idle. In a discussion phase you are either handling messages or waiting for a mention; in a working phase you are working, with \`coral://state\` reads at natural boundaries.

## Work Protocol

### Phase 1: Independent Investigation
- Read the task instruction at $INSTRUCTION_PATH
- Turn the instruction into a BEHAVIOR CHECKLIST: one line per required behavior,
  each with the instruction sentence it comes from. Include defaults, error cases,
  and edge cases the instruction states or implies.
- Explore $REPO_DIR: where the feature plugs in, how similar existing features are
  implemented and registered, how tests are organized and run
- DO NOT communicate yet

### Phase 2: Discussion & Division of Investigation (requires unanimous agreement)
- agent-1 creates a planning thread with all agents
- Each agent proposes which investigation track they will cover, and shares any
  Phase 1 findings that others may not have noticed or that conflict with other
  agents' observations
- Default tracks (adapt to the task; every item below must be owned by someone):
  A. SPEC — the complete behavior checklist, defaults, error cases, edge cases, and
     every ambiguous sentence with a recommended interpretation
  B. INTEGRATION — the exact insertion point (file:line) for every piece of the
     feature, the registration/wiring mechanism (how existing features of this kind
     are registered, exported, enabled, or discovered), existing helpers to reuse,
     and the public API surface (names, signatures, exports) to expose
  C. VERIFICATION — the commands that build and run the test suite OFFLINE in this
     container, how to run a single test file, where new tests go, fixtures and
     test-style conventions, and what the current suite's baseline result is
  D. REGRESSION — existing behavior the change could break, the files that must NOT
     be touched (lockfiles, package manifests, test-framework configuration, CI
     files), and the existing tests most likely to catch a regression
- CRITICALLY CHECK whether the proposed division covers every piece of the feature,
  including implicit requirements the instruction does not state outright
- CRITICALLY CHECK that pieces the instruction requires to work together are
  investigated by the SAME agent, so the interface between them is not guessed
- If your findings conflict with another agent's proposal, discuss and resolve
- If new findings add requirements, agent-1 must update the plan and get everyone's
  agreement again
- You can only APPROVE when ALL conditions are met:
  1. Every checklist behavior and every track is owned by someone
  2. No coupled pieces are split across agents
  3. ALL findings you shared have been discussed (accepted or rejected by the team)
- When you approve, broadcast your APPROVE to all agents (mention everyone)
- ALL agents must explicitly approve before proceeding to Phase 3
- After all agents APPROVE, agent-1 summarizes the final agreed plan (who investigates
  what), creates a shared WORKLOG thread with all four agents as participants, and
  broadcasts both (the plan and the worklog thread id) before moving to Phase 3

### Phase 3: Independent Investigation — with live sharing (WORKING phase)
- Work your track independently; you do not need permission to act
- Read the real code. Verify claims by running things: run the test suite, run a
  single existing test, import the module, exercise the existing code path
- Produce exact evidence: file paths, line numbers, function signatures, snippets,
  commands and their actual output
- agent-1 investigates like everyone else and does NOT start implementing yet
- SHARE AS YOU GO — post to the shared WORKLOG thread (created by agent-1 at the end
  of Phase 2). Because sending costs you nothing and receivers are not interrupted,
  share things at the moment you find them instead of saving them for Phase 4:
  - a registration or wiring mechanism, insertion point, or reusable helper that
    another agent's track depends on;
  - anything that CONTRADICTS the agreed plan or something a teammate stated — e.g.
    the instruction requires a behavior the plan has no insertion point for, or the
    place a teammate said to hook into is not where existing features are actually
    registered — raise it when you see it (URGENT: if their in-flight work depends
    on it) rather than holding it until Phase 4;
  - a verification command that does or does not work offline, and the baseline
    result of the existing suite;
  - an ambiguous sentence of the instruction and the reading you are assuming;
  - approaches you checked and ruled out, so teammates don't burn time on them.
  None of this requires stopping your own work, and none of it requires a reply.
  Mention (@) the agent a note concerns when there is one; plain notes for the whole
  team need no mention. Keep DECISION traffic (approvals, plan changes) OUT of the
  worklog — that belongs in the planning thread.
- RECEIVE by reading \`coral://state\` at natural boundaries (see Working Phases); do NOT
  call \`coral_wait_for_mention\` in this phase. Move to Phase 4 when your track is done.

### Phase 4: Findings, Review & Gap Check (DISCUSSION phase: Communication Loop)
- Create YOUR OWN results thread, add all agents as participants
- Post your complete findings there in the FINDINGS FORMAT below
- Read all other agents' results threads
- In EACH agent's results thread, review their findings:
  - CRITICALLY CHECK: are there factual conflicts with your own findings?
  - CRITICALLY CHECK: does each claim have evidence (file:line, command output)?
  - INFORMATION GAP CHECK: during your Phase 3 work you may have seen code paths,
    registration mechanisms, or conventions relevant to THIS agent's track that they
    did not mention. Point it out: "I saw X which seems related to your track but you
    didn't mention it — did you look into this?"
  - SPEC GAP CHECK: compare the behavior checklist (track A) against the integration
    plan (track B). Is there a checklist item that no insertion point implements? Is
    there an insertion point that no checklist item needs?
  - If you find conflicts or gaps, discuss in THAT agent's results thread with your
    evidence; if re-investigation is needed, agree to go back to Phase 3
- You can only APPROVE an agent's results when BOTH conditions are met:
  1. There are NO unresolved factual conflicts
  2. ALL gaps you raised have been discussed (investigated and addressed, or
     explained why they are not relevant)
- When you approve, broadcast your APPROVE mentioning all agents
- Phase 4 is complete when all agents have APPROVED all other agents' results threads

### Phase 5: Implementation & Review (requires unanimous APPROVE)
- Only after ALL results are approved in Phase 4, agent-1 writes the IMPLEMENTATION
  BRIEF to $BRIEF_PATH (format below) and broadcasts that it is written
- agent-1 creates a new branch, implements the feature following the brief, adds
  tests for every checklist item, runs the full existing suite plus the new tests,
  and only when everything is green creates a review thread with all agents
- All agents review the implementation:
  - Run the verification commands from the brief yourself and report the result
  - Read the diff (git diff against the base branch) and check EVERY checklist item
    against it: which code implements it, and which test exercises it
  - Check the do-not-touch list against the diff
  - APPROVE only if every checklist item is implemented and tested and nothing on
    the do-not-touch list changed; otherwise REQUEST_CHANGES with the exact item,
    file, and what is missing
- agent-1 addresses REQUEST_CHANGES (at most two rounds), re-runs the tests, then
  commits and writes the completion file
- agent-2/3/4: while agent-1 implements, this is a WORKING phase for you: keep verifying
  your own track against the brief, read \`coral://state\` at natural boundaries, and do
  not call \`coral_wait_for_mention\` until agent-1 has opened the review thread (you will
  see it in \`coral://state\`; from then on use the Communication Loop). If you discover
  something that invalidates the brief (a wrong insertion point, a missed behavior),
  post it in the planning thread immediately as URGENT rather than holding it for the
  review

## FINDINGS FORMAT (Phase 4 results thread)
1. Checklist items you own, each with the instruction sentence and its status
   (confirmed requirement / ambiguous, with your recommended reading)
2. Insertion points: file:line, the surrounding function, and a snippet of the
   existing pattern to mirror
3. Registration / wiring: exactly what must be added where for the new code to be
   reachable (export lists, registries, index files, config schemas, CLI tables)
4. Helpers to reuse: name, file:line, signature
5. Verification: the exact commands, their current output, how long they take
6. Regression risks and the do-not-touch list
7. Open questions you could not settle, with evidence either way

## Rules
- agent-2/3/4: do NOT modify files in $REPO_DIR; agent-1: do NOT modify files in
  $REPO_DIR before Phase 5
- Do NOT ask for human input
- SPEC DISCIPLINE: implement what the instruction states, nothing stricter. Never add a
  restriction, validation error, or mutual exclusion the instruction does not state
  (e.g. if it lists two options, assume they can be combined unless it says otherwise).
  The hidden tests exercise the stated behaviors, and an invented restriction fails
  every test that touches it. A team-wide "agreed interpretation" is still a guess:
  record it as an open ambiguity in the brief, and choose the permissive reading.
  When the instruction says an error must "name" something, put the exact names in the
  message, but do not invent further wording the tests might match on.
- Do NOT idle — in a discussion phase wait for mention; in a working phase keep working
  and read \`coral://state\` at natural boundaries (never block there)
- ALWAYS include file paths, line numbers, exact commands and their output
- There is NO network access: do not try to install packages or fetch anything;
  everything the task needs is already in the container
CLAUDE_EOF

if [ "$IS_IMPLEMENTER" = "true" ]; then
  cat >> "$INSTANCE_DIR/CLAUDE.md" << IMPLEMENTER_EOF

## Your Additional Role: Implementer and Chair

You are agent-1. In addition to being an investigator, you:
- Create the planning thread (Phase 2), the shared WORKLOG thread (end of Phase 2),
  and the review thread (Phase 5)
- Write the implementation brief, and you are the ONLY one who edits and commits
  files in $REPO_DIR

### Phase 2 Chair Duties
- When broadcasting the proposed division of investigation, ask all agents to
  critically check:
  "Please critically check:
  1. Does this division cover EVERY behavior in the instruction, including implicit
  ones, and every track (spec, integration, verification, regression)?
  2. Are pieces that must work together investigated by the same agent?
  Only APPROVE if you believe nothing is missing and nothing coupled is split."
- Before declaring Phase 2 complete, read \`coral://state\` and verify that EVERY
  agent has explicitly posted APPROVE. Count the APPROVEs in the thread itself.
- After all APPROVEs: broadcast the final agreed plan, then create the shared WORKLOG
  thread with all four agents as participants and announce its threadId — Phase 3
  live sharing happens there, keeping the planning thread clean for decisions.

### Phase 5 Implementer Duties
0. GATE — do not start Phase 5 early. Before writing the brief, read \`coral://state\` and
   verify that EACH of the four Phase 4 results threads contains an explicit APPROVE
   from all three other agents (12 APPROVEs in total). Count them in the threads
   themselves. If any is missing, call \`coral_wait_for_mention\` and wait for it, and keep reviewing
   the other threads meanwhile. "The investigation was thorough" is NOT a reason to
   skip this gate.
1. Write the brief to $BRIEF_PATH with these sections: merged behavior checklist
   (every item, with its source sentence); for each item the insertion point and the
   test that will cover it; interfaces (names, signatures, exports); verification
   commands; do-not-touch list; open ambiguities and the interpretation chosen.
   Fold in everything posted to the WORKLOG thread, not only the Phase 4 reports.
   Broadcast that the brief is written. Re-read $BRIEF_PATH whenever you are unsure
   what was agreed — it is the source of truth, not your memory.
2. Create a new branch from the repository's current default branch (the instruction
   says main; if main does not exist, branch from the branch currently checked out).
3. Implement, following the brief. When the brief and the code disagree, trust the
   code, and note the deviation in the review thread. Implementation is a WORKING
   phase: between checklist items read \`coral://state\` — a teammate may have posted an
   URGENT correction in the planning or worklog thread — and handle it before moving to
   the next item. Do not call \`coral_wait_for_mention\` while implementing.
4. Add tests for every checklist item, in the repository's own test style and
   location. Run the verification commands from the brief; fix until the full
   existing suite and your new tests are green.
5. Create the review thread with all agents. Post: the branch name, the list of
   files changed, the test commands and their output, and the checklist with the
   file:line that implements each item. Ask everyone:
   "Please run the verification commands yourself, read the diff, and check EVERY
   checklist item against it. APPROVE only if every item is implemented and tested
   and nothing on the do-not-touch list changed; otherwise REQUEST_CHANGES with the
   exact item and what is missing."
6. Address REQUEST_CHANGES, re-run the tests, and re-request review. At most two
   rounds of changes; after the second round, commit what passes.
7. GATE — do not commit early. Before committing, read \`coral://state\` and verify that
   the review thread contains an explicit APPROVE from agent-2, agent-3 AND agent-4
   for the CURRENT version of the diff. If any is missing, call \`coral_wait_for_mention\` and wait
   for it. "All tests pass" is NOT a substitute for the three APPROVEs.
8. Commit ALL tracked changes on the branch (new files included). Never commit files
   outside $REPO_DIR, scratch files, or generated build output that is normally
   ignored. If git refuses because no identity is configured, set user.email and
   user.name locally for this repository and retry.
9. Only after the commit exists, write the completion file:

\`\`\`bash
mkdir -p /logs/agent
{ echo "branch: \$(git -C $REPO_DIR rev-parse --abbrev-ref HEAD)";
  echo "commit: \$(git -C $REPO_DIR rev-parse HEAD)";
  echo "files:"; git -C $REPO_DIR show --stat --oneline HEAD | tail -n +2; } > /logs/agent/answer.txt
\`\`\`

- NEVER write the completion file before the commit exists
- NEVER leave uncommitted changes: the grader only sees committed work
IMPLEMENTER_EOF
else
  cat >> "$INSTANCE_DIR/CLAUDE.md" << 'PEER_EOF'

## Submission
Do NOT modify or commit files in the repository. Do NOT write the completion file.
Only agent-1 does that.
PEER_EOF
fi

export PATH="$HOME/.local/bin:$PATH"

echo ">>> Launching Claude Code for agent: $CORAL_AGENT_ID (implementer=$IS_IMPLEMENTER, L2.5)"
cd "$INSTANCE_DIR"

LOG_FILE="$SCRIPT_DIR/instances/$CORAL_SESSION_ID/${CORAL_AGENT_ID}-claude-code.txt"

if [ "$IS_IMPLEMENTER" = "true" ]; then
  PROMPT="Read the task instruction at $INSTRUCTION_PATH. Begin Phase 1: build the behavior checklist and explore the repo at $REPO_DIR. Then proceed to Phase 2: create a planning thread with all agents (agent-1, agent-2, agent-3, agent-4)."
else
  PROMPT="Read the task instruction at $INSTRUCTION_PATH. Begin Phase 1: build the behavior checklist and explore the repo at $REPO_DIR. Then call coral_wait_for_mention to wait for agent-1 to create the planning thread."
fi

exec claude --verbose --output-format=stream-json --permission-mode=bypassPermissions --effort high --print -- "$PROMPT" 2>&1 </dev/null | tee "$LOG_FILE"
