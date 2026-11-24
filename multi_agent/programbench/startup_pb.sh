#!/bin/bash
# ProgramBench TEAM startup script — launched by the message server once per agent.
# One script for both conditions; PB_VARIANT selects the communication rules:
#   l25  fixed windows: MCP tools, blocking receive, silence outside windows
#   l3   share as you go: shell scripts, background watcher (passive awareness)
#   l3h  share as you go: shell scripts to send; a Claude Code PostToolUse hook delivers
#        new peer messages after every tool call (harness-level passive awareness)
#   l25p L2.5 windows kept; the working phases between them use the L3 share-as-you-go
#        rules, but nothing is pushed: agents receive by reading coral://state themselves
# Everything else in the prompt (roles, ownership, split, tree rules, bells) is
# generated from the same text for both conditions.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTANCE_DIR="$SCRIPT_DIR/instances/$CORAL_SESSION_ID/$CORAL_AGENT_ID"
mkdir -p "$INSTANCE_DIR/.claude"
STARTUP_LOG="$SCRIPT_DIR/instances/$CORAL_SESSION_ID/${CORAL_AGENT_ID}-startup.log"
exec > >(tee -a "$STARTUP_LOG") 2>&1

VARIANT="${PB_VARIANT:-l3}"
PB_DIR="${PB_DIR:-/tmp/pb}"
WS_DIR="${PB_WORKSPACE:-/workspace}"
BUDGET="${PB_BUDGET_MIN:-60}"
MODEL="${PB_MODEL:-claude-opus-5-5}"
EFFORT="${PB_EFFORT:-xhigh}"
AGENT="$CORAL_AGENT_ID"
SCRATCH="/tmp/scratch-$AGENT"
mkdir -p "$SCRATCH"
export HOME="${HOME:-/home/agent}"
export PATH="$PB_DIR/bin:$HOME/.local/bin:$PATH"
export GIT_AUTHOR_NAME="$AGENT" GIT_COMMITTER_NAME="$AGENT"
export GIT_AUTHOR_EMAIL="$AGENT@team.local" GIT_COMMITTER_EMAIL="$AGENT@team.local"

printf '%s\n' "$CORAL_CONNECTION_URL" > "$INSTANCE_DIR/url.txt"; chmod 600 "$INSTANCE_DIR/url.txt"
echo "=== ProgramBench team agent ($VARIANT) ==="
echo "Agent: $AGENT  Session: $CORAL_SESSION_ID  URL: $CORAL_CONNECTION_URL"
echo "Instance dir: $INSTANCE_DIR  model=$MODEL effort=$EFFORT budget=${BUDGET}m"

# ---------------------------------------------------------------- bell timer (both)
mkdir -p "$INSTANCE_DIR/scripts"
cat > "$INSTANCE_DIR/scripts/next_bell.sh" <<WRAP_EOF
#!/bin/bash
exec bash $PB_DIR/next_bell.sh
WRAP_EOF

# ------------------------------------------------- communication plumbing per variant
if [ "$VARIANT" = "l25" ] || [ "$VARIANT" = "l25p" ]; then
  cat > "$INSTANCE_DIR/.mcp.json" <<EOF
{ "mcpServers": { "coral": { "type": "http", "url": "$CORAL_CONNECTION_URL", "timeout": 1200000 } } }
EOF
  cat > "$INSTANCE_DIR/.claude/settings.local.json" <<EOF
{ "permissions": { "allow": [ "mcp__coral" ] }, "enabledMcpjsonServers": [ "coral" ], "enableAllProjectMcpServers": true }
EOF
  MCP_FLAGS=()
else
  mkdir -p "$INSTANCE_DIR/scripts/_lib"
  cp "$SCRIPT_DIR"/passive_scripts/coral_mcp_lib.sh "$SCRIPT_DIR"/passive_scripts/coral_json.py \
     "$SCRIPT_DIR"/passive_scripts/wait_for_mention.sh "$SCRIPT_DIR"/passive_scripts/send_message.sh \
     "$SCRIPT_DIR"/passive_scripts/create_thread.sh "$SCRIPT_DIR"/passive_scripts/read_resource.sh \
     "$INSTANCE_DIR/scripts/_lib/"
  if [ "$VARIANT" = "l3" ]; then
  cat > "$INSTANCE_DIR/scripts/wait_for_mention.sh" <<WRAP_EOF
#!/bin/bash
# usage: wait_for_mention.sh [maxWaitMs=60000] [maxRounds=20]
exec bash "$INSTANCE_DIR/scripts/_lib/wait_for_mention.sh" "$CORAL_CONNECTION_URL" "\${1:-60000}" "\${2:-20}"
WRAP_EOF
  fi
  cat > "$INSTANCE_DIR/scripts/send_message.sh" <<WRAP_EOF
#!/bin/bash
# usage: send_message.sh <threadId> <content> [mentionsCSV]
exec bash "$INSTANCE_DIR/scripts/_lib/send_message.sh" "$CORAL_CONNECTION_URL" "\$@"
WRAP_EOF
  cat > "$INSTANCE_DIR/scripts/create_thread.sh" <<WRAP_EOF
#!/bin/bash
# usage: create_thread.sh <threadName> [participantsCSV]   (last line: threadId=<id>)
exec bash "$INSTANCE_DIR/scripts/_lib/create_thread.sh" "$CORAL_CONNECTION_URL" "\$@"
WRAP_EOF
  cat > "$INSTANCE_DIR/scripts/read_resource.sh" <<WRAP_EOF
#!/bin/bash
exec bash "$INSTANCE_DIR/scripts/_lib/read_resource.sh" "$CORAL_CONNECTION_URL"
WRAP_EOF
  MCP_FLAGS=(--strict-mcp-config --mcp-config '{"mcpServers":{}}')
  if [ "$VARIANT" = "l3h" ]; then
    # harness-delivered receive: Claude Code runs the inbox hook after every tool call
    # (success or failure) and attaches new peer messages to the tool result
    rm -f "$INSTANCE_DIR/scripts/_lib/wait_for_mention.sh"
    HOOK_CMD="python3 $PB_DIR/inbox_hook.py $INSTANCE_DIR"
    cat > "$INSTANCE_DIR/.claude/settings.local.json" <<EOF
{ "hooks": {
    "PostToolUse":        [ { "hooks": [ { "type": "command", "command": "$HOOK_CMD", "timeout": 20 } ] } ],
    "PostToolUseFailure": [ { "hooks": [ { "type": "command", "command": "$HOOK_CMD", "timeout": 20 } ] } ]
} }
EOF
  fi
fi
chmod +x "$INSTANCE_DIR/scripts/"*.sh "$INSTANCE_DIR/scripts/_lib/"*.sh 2>/dev/null

# ---------------------------------------------------------------- probe axis per agent
case "$AGENT" in
  agent-1) AXIS="INTERFACE and BUILD: what the reference exposes about its internal representation (dump/list/introspection commands), the exact output format, how it is invoked; choose the implementation language and the module layout; start the core skeleton as soon as you know enough." ;;
  agent-2) AXIS="INPUTS: the input side (readers, languages, accepted syntaxes, input options); what the docs enumerate; which inputs are large; collect reference outputs for the biggest ones." ;;
  agent-3) AXIS="OUTPUTS: the output side (writers, output formats, fields, output options); what the docs enumerate; which outputs are large; collect reference outputs for the biggest ones." ;;
  *)       AXIS="OPTIONS and TEST WEIGHT: the command-line options, exit codes, error messages, edge behaviors (empty input, missing file, conflicting flags); and an estimate of which features probably carry the most hidden tests (size of their documentation and option surface is the clue)." ;;
esac
BELL_TABLE="$(awk -F'\t' '{printf "  - minute %3d: %s\n", $1, $2}' "$PB_DIR/bells.txt")"
bell_min() { awk -F'\t' -v pat="$1" 'index($2, pat) == 1 {print $1; exit}' "$PB_DIR/bells.txt"; }
W1O=$(bell_min "W1 OPEN"); W1C=$(bell_min "W1 CLOSE"); W2O=$(bell_min "W2 OPEN"); W2C=$(bell_min "W2 CLOSE")
W3O=$(bell_min "W3 OPEN"); W3C=$(bell_min "W3 CLOSE"); FRZ=$(bell_min "FREEZE")
# P0 ends at minute 5 and the SPLIT is due at minute 10 for every real budget (40 or 60
# minutes, so the first ten minutes are comparable); smoke budgets under 30 min scale them.
if [ "$BUDGET" -ge 30 ]; then
  P0_MIN=5; SPLIT_MIN=10
else
  P0_MIN=$(( (BUDGET * 5 + 30) / 60 )); [ "$P0_MIN" -lt 1 ] && P0_MIN=1
  SPLIT_MIN=$(( (BUDGET * 10 + 30) / 60 )); [ "$SPLIT_MIN" -le "$P0_MIN" ] && SPLIT_MIN=$((P0_MIN + 1))
fi

# ---------------------------------------------------------------- CLAUDE.md (shared text)
cat > "$INSTANCE_DIR/CLAUDE.md" <<CLAUDE_EOF
# ProgramBench Team

You are $AGENT, one of 4 agents rebuilding ONE program together under a hard wall-clock
budget of $BUDGET minutes. Your peers: agent-1, agent-2, agent-3, agent-4.

- Task instruction (the benchmark rules; read it first): $PB_DIR/prompt.md
- Shared working tree: $WS_DIR  (all four of you edit the SAME directory)
- Reference binary: $WS_DIR/executable  (execute-only; run it as often as you like)
- Your private scratch directory: $SCRATCH  (golden cases, probe scripts, notes)

## How the team is graded

At the deadline the whole $WS_DIR is taken exactly as it is, uncommitted files included.
The grader runs ./compile.sh on a fresh copy, then checks ./executable against the
reference program test by test. Partial credit is real, there is no natural stopping
point, and the team gets ONE score for its single tree. A tree whose compile.sh fails
scores zero, whatever is inside it.

## Roles and ownership

- agent-1 owns the CORE: the data model / intermediate representation, command-line
  parsing and dispatch, the module registry and loader, compile.sh, and the reference's
  own dump or listing outputs if it has them. Nobody else edits core files. If you need
  a core change, ask agent-1 (when and how is governed by the communication rules
  below) and keep working inside your own module meanwhile.
- agent-2, agent-3, agent-4 own MODULES. Each module lives in its own file(s) under the
  module directory that agent-1 announces in the SPLIT. You edit only files you own and
  you may create new module files in your own area at any time.
- Ownership covers an output (a parser, a writer, an option group), not an algorithm.
  When you finish a module, take the next unowned one from the SPLIT list, or add one.
  The split grows as the team discovers work; nobody waits for a complete plan.

## P0: probe (first ~$P0_MIN minutes, everybody in parallel)

Your probe axis: $AXIS

End P0 with a BRIEF (at most 15 lines): what the reference exposes, the modules you
propose on your axis with a rough size, and the two modules you want to own first.

## SPLIT (posted by agent-1 once the core skeleton compiles, target: minute $SPLIT_MIN)

The SPLIT states: implementation language; module directory and file naming rule; the
core interface (how a module registers itself, the data it receives and must produce,
with one concrete example); the module list with an owner per module and a priority
order (biggest expected test weight first); the fresh-copy check command. Anyone may
append modules later and claim unowned ones by saying CLAIM <module>.

## Shared-tree rules (hard)

1. Edit only files you own. Never reformat, rename, delete, or "fix" a peer's file.
2. The core must tolerate broken modules: agent-1 implements module discovery with a
   per-module try/except around the import so that one half-written module disables
   that module only, never the executable. Until that loader exists, modules stay out
   of the registry.
3. Keep ./executable working for everyone. Finish an edit before leaving a file in a
   state that breaks import or compile. Test your module through the real ./executable
   path, not only in isolation.
4. In $WS_DIR, ./executable IS the reference and cannot be deleted or replaced, so never
   run ./compile.sh inside $WS_DIR. Build and test in a fresh copy, exactly as the grader
   does (it copies the tree without the reference, runs ./compile.sh, then tests):
   rm -rf /tmp/fresh-$AGENT && mkdir /tmp/fresh-$AGENT && tar -C $WS_DIR --exclude=./executable -cf - . | tar -C /tmp/fresh-$AGENT -xf - && (cd /tmp/fresh-$AGENT && ./compile.sh && <one smoke invocation of ./executable>)
   Running your entry point directly (e.g. python3 src/main.py) is fine for quick checks.
   agent-1 runs the fresh-copy check at least every 15 minutes and again right after FREEZE.
5. Golden cases: for each module keep reference outputs in $SCRATCH (input, exact
   command, reference output) and diff your implementation against them. Prefer breadth:
   many small inputs covering the documented options over one deep case.
6. Nothing in $WS_DIR may read, exec, wrap, or embed ./executable (benchmark rule).
   The reference is for probing only.

## Git rules

- Commit your own files often: git add <your paths>  then  git commit -m "<module>: <what>".
  Your author name is preset to $AGENT, so history shows who built what.
- Never git add -A, git add ., git commit -a, checkout, restore, reset --hard, stash,
  clean, rebase, or merge: in a shared tree they stage or destroy a peer's uncommitted
  work. A guard refuses them. To undo your own file: git show HEAD:<path> > <path>.
- Grading does not need commits (the tree is taken as-is); commits are history.

## Time and bells

The budget runs from the moment all four of you were started (the runner's clock, not
your session). The harness rings BELLS at fixed minutes. You receive them by keeping
EXACTLY ONE bell timer running as a BACKGROUND Bash task (run_in_background=true):

  bash scripts/next_bell.sh

When it finishes, read its output and relaunch it at once. Bells are the clock and carry
no peer information; they are never messages from a peer. Schedule:
$BELL_TABLE
At FREEZE stop editing $WS_DIR. At the deadline every process is killed and the tree is
snapshotted. A snapshot is also taken every 5 minutes, so progress is never lost.

## Message formats (keep them short; evidence is a command and its output)

- BRIEF: P0 result, format above.
- SPLIT: format above.
- CLAIM <module> / DONE <module> (<n> golden cases pass): taking or finishing a module.
- FACT: a cross-cutting behavior of the reference that others will hit, with the exact
  command and output (escaping rules, wrapping width, ordering, defaults).
- FAIL @owner <module>: input, reference output versus ours, exact command.
- REQUEST @agent-1: a core change you need, with the smallest interface that would do.
- URGENT prefix: the receiver's in-flight work is affected (a broken build, an interface
  that changed, an assumption that is wrong). FYI prefix: no reply needed.

## General rules

- Do not ask for human input; do not idle; keep your bell timer alive.
- SPEC DISCIPLINE: the reference's observed behavior is the specification. When the docs
  and the binary disagree, the binary wins. Never invent a restriction or error the
  reference does not produce.
- There is no network: everything you need is in the container.
- The run is killed at the deadline, so never leave the tree in a state that does not
  compile; finish small, commit, continue.
CLAUDE_EOF

share_section() {  # share-as-you-go rules and timeline: identical text for l3 and l3h
cat >> "$INSTANCE_DIR/CLAUDE.md" <<CLAUDE_EOF

SHARE AS YOU GO. Sending costs you nothing and does not interrupt the receiver, so post
things at the moment they happen instead of saving them:
- your BRIEF at about minute $P0_MIN;
- agent-1: the SPLIT the moment the core skeleton compiles (target minute $SPLIT_MIN), and every
  later change to the core interface as URGENT;
- CLAIM when you take a module, DONE when its golden cases pass;
- FACT when you observe a cross-cutting behavior; FAIL @owner the moment you see a peer
  module disagree with the reference; URGENT FAIL if the tree no longer compiles;
- REQUEST @agent-1 as soon as you need a core change, and keep working around it until
  the answer arrives; agent-1 answers REQUESTs before starting its next piece of work;
- REVIEW is continuous: when a peer posts DONE for a module and you hold golden cases
  that touch it, run them and post PASS or FAIL.
No windows, no fixed phases after P0.

## Timeline (this condition)

  0-$P0_MIN    P0 probe (agent-1 creates the team thread; findings may be shared at any time)
  ~$P0_MIN     everybody posts BRIEF
  ~$SPLIT_MIN    agent-1 posts the SPLIT when the skeleton compiles; peers claim and start
  $SPLIT_MIN-$FRZ  implement, share as you go, continuous review
  $FRZ-$BUDGET  FREEZE: stop editing; final snapshot at the deadline
CLAUDE_EOF
}

# ---------------------------------------------------------------- variant sections
if [ "$VARIANT" = "l25" ]; then
cat >> "$INSTANCE_DIR/CLAUDE.md" <<CLAUDE_EOF

## Communication: fixed windows, blocking receive (this condition)

You talk to your peers ONLY through the coral MCP tools (coral_send_message,
coral_wait_for_mention, coral_create_thread, and the coral://state resource), and ONLY
while a window is open. The team thread is created by agent-1 at the start; find its
id in coral://state when the first window opens.

Outside a window you are SILENT: you do not send, you do not call coral_wait_for_mention,
you do not read coral://state. You implement, and you write what you want to tell the
team into $SCRATCH/pending.md for the next window.

Windows are opened and closed by bells:
  W1 (minute $W1O-$W1C)  split window
  W2 (minute $W2O-$W2C) review window
  W3 (minute $W3O-$W3C) wrap-up window

Inside a window run this loop until the CLOSE bell:
  1. Post what the window asks for (below), mentioning all peers, in the team thread.
  2. Call coral_wait_for_mention (maxWaitMs 60000).
  3. When it returns, read coral://state and handle every message you have not handled
     yet (reply, review, update your plan).
  4. Back to 2.
Leave the loop when the CLOSE bell arrives (your bell timer finishes with it): finish the
reply you are writing, then go silent again. If a window closes before you got what you
needed, work around it inside your own module.

Window content:
- W1: everybody posts BRIEF. agent-1 posts the SPLIT after reading the briefs (well before
  the window closes, even if a brief is missing). Everybody replies ACK or one concrete change.
  agent-1 posts the final SPLIT before the window closes.
- W2: everybody posts STATUS: DONE and CLAIM lines, FACTs, REQUESTs, FAILs collected in
  pending.md. Then REVIEW: run at least one peer module against your own golden cases and
  post PASS or FAIL for it. agent-1 answers every REQUEST (does the core change now, or
  says what to do instead) and reposts the module list with owners.
- W3: everybody posts final STATUS and open FAILs. agent-1 assigns the fixes for the
  fix-only phase and runs the fresh-copy check.

## Timeline (this condition)

  0-$W1O    P0 probe, silent (agent-1 creates the team thread, no discussion yet)
  $W1O-$W1C   W1 split window
  $W1C-$W2O  implement, silent
  $W2O-$W2C  W2 review window
  $W2C-$W3O  implement, silent
  $W3O-$W3C  W3 wrap-up window
  $W3C-$FRZ  fix only what W3 assigned, silent
  $FRZ-$BUDGET  FREEZE: stop editing; final snapshot at the deadline
CLAUDE_EOF
elif [ "$VARIANT" = "l25p" ]; then
cat >> "$INSTANCE_DIR/CLAUDE.md" <<CLAUDE_EOF

## Communication: fixed windows for discussion, share-as-you-go working phases (this condition)

You talk to your peers ONLY through the coral MCP tools (coral_send_message,
coral_wait_for_mention, coral_create_thread, and the coral://state resource). The team
thread is created by agent-1 at the start; find its id in coral://state.

Two kinds of phase alternate, opened and closed by bells:
  W1 (minute $W1O-$W1C)  split window
  W2 (minute $W2O-$W2C) review window
  W3 (minute $W3O-$W3C) wrap-up window
  everything else after P0 is a WORKING phase.

Inside a window run this loop until the CLOSE bell:
  1. Post what the window asks for (below), mentioning all peers, in the team thread.
  2. Call coral_wait_for_mention (maxWaitMs 60000).
  3. When it returns, read coral://state and handle every message you have not handled
     yet (reply, review, update your plan).
  4. Back to 2.
Leave the loop when the CLOSE bell arrives (your bell timer finishes with it): finish the
reply you are writing, then go back to working.

In a WORKING phase you SHARE AS YOU GO (rules below), with one difference in how you
RECEIVE: nothing is pushed to you. There is no watcher and no hook, and
coral_wait_for_mention is NOT allowed outside a window (it blocks you). To learn what your
peers posted you read coral://state yourself: it is a full dump of every thread, so work
out what is new since you last read it and handle it. Read it at natural boundaries (when
you finish a piece of work, before you claim the next module, after you send something
that needs an answer, when a bell rings); do not spin on it, and never stop working to
wait for a reply.

Window content:
- W1: everybody posts BRIEF. agent-1 posts the SPLIT after reading the briefs (well before
  the window closes, even if a brief is missing). Everybody replies ACK or one concrete change.
  agent-1 posts the final SPLIT before the window closes.
- W2: everybody posts STATUS: DONE and CLAIM lines, open FACTs, REQUESTs and FAILs. Then
  REVIEW: run at least one peer module against your own golden cases and post PASS or FAIL
  for it. agent-1 answers every REQUEST (does the core change now, or says what to do
  instead) and reposts the module list with owners.
- W3: everybody posts final STATUS and open FAILs. agent-1 assigns the fixes for the
  fix-only phase and runs the fresh-copy check.

SHARE AS YOU GO (working phases). Sending costs you nothing and does not interrupt the
receiver, so post things at the moment they happen instead of saving them:
- agent-1: every change to the core interface as URGENT;
- CLAIM when you take a module, DONE when its golden cases pass;
- FACT when you observe a cross-cutting behavior; FAIL @owner the moment you see a peer
  module disagree with the reference; URGENT FAIL if the tree no longer compiles;
- REQUEST @agent-1 as soon as you need a core change, and keep working around it until
  the answer arrives; agent-1 answers REQUESTs when it next reads coral://state, before
  starting its next piece of work;
- REVIEW is continuous: when you read a peer's DONE for a module and you hold golden cases
  that touch it, run them and post PASS or FAIL.

## Timeline (this condition)

  0-$W1O    P0 probe (agent-1 creates the team thread; findings may be shared at any time)
  $W1O-$W1C   W1 split window
  $W1C-$W2O  working phase: implement, share as you go, receive by reading coral://state
  $W2O-$W2C  W2 review window
  $W2C-$W3O  working phase: implement, share as you go, receive by reading coral://state
  $W3O-$W3C  W3 wrap-up window
  $W3C-$FRZ  fix only what W3 assigned (post FIXED; receive by reading coral://state)
  $FRZ-$BUDGET  FREEZE: stop editing; final snapshot at the deadline
CLAUDE_EOF
elif [ "$VARIANT" = "l3" ]; then
cat >> "$INSTANCE_DIR/CLAUDE.md" <<CLAUDE_EOF

## Communication: share as you go, passive receive (this condition)

You talk to your peers ONLY through the shell scripts in ./scripts; you do NOT have MCP
tools. Your identity is baked in; never pass a URL.

- bash scripts/wait_for_mention.sh   the watcher: blocks until you are mentioned or any
  new message appears, or ~20 minutes pass. Its output is self-contained (the new message
  plus a full dump of all threads). Run it ONLY as a background task.
- bash scripts/send_message.sh <threadId> "<content>" [mentionsCSV]
- bash scripts/create_thread.sh "<name>" "<participantsCSV>"   (last line: threadId=<id>)
- bash scripts/read_resource.sh   the full state; use it after a context compaction, or
  for a proactive check. Not needed after a watcher notification.

The team thread is created by agent-1 at the start, with all four agents as participants;
every message goes there.

Passive awareness (how you receive):
1. Keep EXACTLY ONE watcher running at all times as a BACKGROUND Bash task
   (run_in_background=true): bash scripts/wait_for_mention.sh
   So you always have two background tasks: the watcher and the bell timer.
2. Launch the watcher right after reading the instruction; keep it alive until FREEZE.
3. When a watcher finishes: relaunch a fresh one at once, then read the finished one's
   output and handle what is new. Never run two watchers at once, never leave a gap.
4. Sending is fire-and-forget: send, then continue your work; replies reach you through
   the watcher. Never stop working to wait for a reply.
5. Handling: URGENT, or something that changes what you are doing, now; otherwise finish
   the piece of work you are in, then respond. Never silently drop a message.
CLAUDE_EOF
share_section
else
cat >> "$INSTANCE_DIR/CLAUDE.md" <<CLAUDE_EOF

## Communication: share as you go, harness-delivered receive (this condition)

You talk to your peers ONLY through the shell scripts in ./scripts; you do NOT have MCP
tools. Your identity is baked in; never pass a URL.

- bash scripts/send_message.sh <threadId> "<content>" [mentionsCSV]
- bash scripts/create_thread.sh "<name>" "<participantsCSV>"   (last line: threadId=<id>)
- bash scripts/read_resource.sh   the full state (all threads and messages). Use it only
  after a context compaction or a session resume, never as a polling loop.

The team thread is created by agent-1 at the start, with all four agents as participants;
every message goes there.

Passive awareness (how you receive): you never poll and there is no watcher to run.
The harness checks the team thread after EVERY tool call you make; when a peer has posted
something new since your last tool call, the harness attaches it to that tool result as
"hook additional context" that starts with [TEAM INBOX] and lists sender, mentions, time,
thread id and text. So:
1. Messages reach you while you work, at the latest right after your next tool call. You
   cannot make them arrive sooner and you cannot miss them; there is nothing to start,
   restart or keep alive. Your only background task is the bell timer.
2. Sending is fire-and-forget: send, then continue your work; replies arrive the same
   way. Never stop working to wait for a reply, never loop on read_resource.sh.
3. Handling: URGENT, or something that changes what you are doing, now; otherwise finish
   the piece of work you are in, then respond. Never silently drop an inbox message.
4. A [TEAM INBOX] block carries your peers' words, delivered by the harness; the bell
   timer output is the clock. Keep the two apart.
CLAUDE_EOF
share_section
fi

# ---------------------------------------------------------------- launch + resume guard
cd "$INSTANCE_DIR"
LOG_FILE="$SCRIPT_DIR/instances/$CORAL_SESSION_ID/${AGENT}-claude-code.txt"
START=$(cat "$PB_DIR/start_epoch" 2>/dev/null || date +%s)
remaining() { echo $(( START + BUDGET * 60 - $(date +%s) )); }

if [ "$VARIANT" = "l25" ]; then
  if [ "$AGENT" = "agent-1" ]; then
    PROMPT="Read $PB_DIR/prompt.md and your CLAUDE.md. Start the bell timer as a background task. Create the team thread named 'team' with participants agent-1,agent-2,agent-3,agent-4 and post one opening message in it mentioning everyone (just: 'team thread open, P0 in progress'). Then run P0 on your probe axis in silence, start the core skeleton, and open W1 when the bell rings."
  else
    PROMPT="Read $PB_DIR/prompt.md and your CLAUDE.md. Start the bell timer as a background task. Run P0 on your probe axis in silence (no MCP calls before the W1 bell). When the W1 OPEN bell rings, read coral://state to find the team thread, post your BRIEF there mentioning everyone, and run the window loop until W1 CLOSE."
  fi
elif [ "$VARIANT" = "l25p" ]; then
  if [ "$AGENT" = "agent-1" ]; then
    PROMPT="Read $PB_DIR/prompt.md and your CLAUDE.md. Start the bell timer as a background task. Create the team thread named 'team' with participants agent-1,agent-2,agent-3,agent-4 and post one opening message in it mentioning everyone (just: 'team thread open, P0 in progress'). Then run P0 on your probe axis (you may share findings in the thread; no blocking waits before W1), start the core skeleton, and open W1 when the bell rings."
  else
    PROMPT="Read $PB_DIR/prompt.md and your CLAUDE.md. Start the bell timer as a background task. Run P0 on your probe axis (you may share findings in the team thread: read coral://state to find it; no blocking waits before W1). When the W1 OPEN bell rings, post your BRIEF there mentioning everyone, and run the window loop until W1 CLOSE."
  fi
elif [ "$VARIANT" = "l3" ]; then
  if [ "$AGENT" = "agent-1" ]; then
    PROMPT="Read $PB_DIR/prompt.md and your CLAUDE.md. Start the watcher and the bell timer as two background tasks. Create the team thread named 'team' with participants agent-1,agent-2,agent-3,agent-4 and post one opening message mentioning everyone (threadId in it). Then run P0 on your probe axis, start the core skeleton, post your BRIEF at about minute $P0_MIN and the SPLIT as soon as the skeleton compiles."
  else
    PROMPT="Read $PB_DIR/prompt.md and your CLAUDE.md. Start the watcher and the bell timer as two background tasks. Run P0 on your probe axis; the watcher will bring you the team thread id. Post your BRIEF there at about minute $P0_MIN, claim modules when the SPLIT arrives, and share as you go."
  fi
else
  if [ "$AGENT" = "agent-1" ]; then
    PROMPT="Read $PB_DIR/prompt.md and your CLAUDE.md. Start the bell timer as a background task (your only background task; peer messages arrive by themselves in [TEAM INBOX] blocks after your tool calls). Create the team thread named 'team' with participants agent-1,agent-2,agent-3,agent-4 and post one opening message mentioning everyone (threadId in it). Then run P0 on your probe axis, start the core skeleton, post your BRIEF at about minute $P0_MIN and the SPLIT as soon as the skeleton compiles."
  else
    PROMPT="Read $PB_DIR/prompt.md and your CLAUDE.md. Start the bell timer as a background task (your only background task; peer messages arrive by themselves in [TEAM INBOX] blocks after your tool calls). Run P0 on your probe axis; the team thread id will reach you that way. Post your BRIEF there at about minute $P0_MIN, claim modules when the SPLIT arrives, and share as you go."
  fi
fi
RESUME_PHASES="inside a window, run the window loop; in a silent phase, keep implementing your modules and do not communicate; in the share-as-you-go condition, keep implementing and sharing; after FREEZE, do not edit the tree."
if [ "$VARIANT" = "l3h" ]; then
  RESUME_BG="First restart your background bell timer; there is no watcher in your condition, peer messages keep arriving by themselves in [TEAM INBOX] blocks after your tool calls."
elif [ "$VARIANT" = "l25p" ]; then
  RESUME_BG="First restart your background bell timer, then read coral://state to catch up on what your peers posted while you were away."
  RESUME_PHASES="inside a window, run the window loop; in a working phase, keep implementing and sharing, and read coral://state yourself to receive (no blocking waits outside a window); after FREEZE, do not edit the tree."
else
  RESUME_BG="First restart your background bell timer (and, in the share-as-you-go condition, your watcher)."
fi

CLAUDE_ARGS=(--verbose --output-format=stream-json --permission-mode=bypassPermissions
  --model "$MODEL" --effort "$EFFORT" --settings '{"fastMode": false}'
  --disallowedTools "Agent,Workflow,ScheduleWakeup,CronCreate,CronDelete,CronList,WebSearch,WebFetch"
  "${MCP_FLAGS[@]}")

echo ">>> launching claude for $AGENT ($VARIANT) remaining=$(remaining)s"
claude "${CLAUDE_ARGS[@]}" --print -- "$PROMPT" 2>&1 </dev/null | python3 -u "$PB_DIR/ts.py" | tee "$LOG_FILE"
RELAUNCH=0
while [ ! -f "$PB_DIR/STOP" ] && [ "$(remaining)" -gt 120 ]; do
  RELAUNCH=$((RELAUNCH + 1))
  mins=$(( $(remaining) / 60 ))
  elapsed_min=$(( ( $(date +%s) - START ) / 60 ))
  # the most recent bell tells the agent which phase it is in (window, silent, freeze)
  last_bell=$(awk -F'\t' -v e="$elapsed_min" '$1 <= e {t=$2} END {print (t ? t : "none yet (still P0)")}' "$PB_DIR/bells.txt")
  echo ">>> [resume-guard] claude exited before the deadline; relaunch #$RELAUNCH elapsed=${elapsed_min}m remaining=${mins}m last_bell=$last_bell" | tee -a "$LOG_FILE"
  sleep 10
  claude "${CLAUDE_ARGS[@]}" --continue --print -- "Your session was resumed because your process exited before the deadline. Team clock: minute ${elapsed_min} of ${BUDGET}, about ${mins} minutes remain. The most recent bell was: '${last_bell}'. Re-read your CLAUDE.md. ${RESUME_BG} Then continue your role exactly as the rules for THIS phase say: ${RESUME_PHASES} Check the tree still compiles before anything else. Never stop with uncommitted broken files." 2>&1 </dev/null | python3 -u "$PB_DIR/ts.py" | tee -a "$LOG_FILE"
done
echo ">>> [resume-guard] exiting (stop=$([ -f "$PB_DIR/STOP" ] && echo yes || echo no), relaunches=$RELAUNCH)" | tee -a "$LOG_FILE"
