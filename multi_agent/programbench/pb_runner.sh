#!/bin/bash
# In-container clock for a ProgramBench TEAM run (runs as the `agent` user).
#  1. writes the start epoch (the team clock), takes snapshot t000
#  2. creates the message-server session (which launches the 4 agents)
#  3. every 10 s: snapshot at each PB_SNAP_MIN boundary, log sync every minute
#  4. at PB_BUDGET_MIN: touch STOP, kill every claude process, final snapshot, save logs
set -u
PB_DIR="${PB_DIR:-/tmp/pb}"
WS_DIR="${PB_WORKSPACE:-/workspace}"
CORAL_WS="${CORAL_WS:-/tmp/coral-workspace}"
AGENT_DIR="${CORAL_AGENT_DIR:-$CORAL_WS/pb-agent}"
OUT=/logs/agent
SNAPS=$OUT/snapshots
BUDGET_MIN="${PB_BUDGET_MIN:-60}"
SNAP_MIN="${PB_SNAP_MIN:-5}"
RUNLOG=$OUT/run.log
mkdir -p "$SNAPS" "$OUT/coral-state"
log() { echo "$(date -u +%FT%TZ) [runner] $*" | tee -a "$RUNLOG"; }

snapshot() {
  local f="$SNAPS/$1.tar.gz"
  tar -czf "$f" --exclude=./executable --exclude=./target --exclude=./node_modules \
      --exclude='__pycache__' --exclude=./.cache --exclude=./.claude \
      -C "$WS_DIR" . 2>>"$RUNLOG"
  log "snapshot $1 elapsed=$(( $(date +%s) - START ))s bytes=$(stat -c %s "$f" 2>/dev/null || echo 0)"
}
dump_state() {  # full message-server state (all threads, messages, timestamps) as seen by agent-1
  local u; u=$(find "$AGENT_DIR/instances/" -path '*/agent-1/url.txt' 2>/dev/null | head -1)
  [ -n "$u" ] || { echo "dump_state: no agent-1 url.txt yet" >> "$OUT/dump-state.err"; return 0; }
  timeout 60 bash "$AGENT_DIR/passive_scripts/read_resource.sh" "$(cat "$u")" > "$OUT/coral-state.md.tmp" 2>> "$OUT/dump-state.err" \
    && mv "$OUT/coral-state.md.tmp" "$OUT/coral-state.md" || echo "dump_state failed rc=$? at $(date -u +%T)" >> "$OUT/dump-state.err"
}
sync_logs() {
  cp "$CORAL_WS/coral-server.log" "$OUT/" 2>/dev/null || true
  cp "$CORAL_WS/session-response.json" "$OUT/" 2>/dev/null || true
  find "$AGENT_DIR/instances/" -name '*-claude-code.txt' -exec cp {} "$OUT/" \; 2>/dev/null || true
  find "$AGENT_DIR/instances/" -name '*-startup.log' -exec cp {} "$OUT/" \; 2>/dev/null || true
  find "$AGENT_DIR/instances/" -name '*-inbox.log' -exec cp {} "$OUT/" \; 2>/dev/null || true
}

START=$(date +%s)
echo "$START" > "$PB_DIR/start_epoch"
rm -f "$PB_DIR/STOP"
DEADLINE=$((START + BUDGET_MIN * 60))
log "start variant=${PB_VARIANT:-?} model=${PB_MODEL:-?} effort=${PB_EFFORT:-?} budget=${BUDGET_MIN}m snap=${SNAP_MIN}m"
log "bells: $(tr '\t' '=' < "$PB_DIR/bells.txt" | tr '\n' ';')"
snapshot t000

# launch the team
curl --noproxy '*' -s -X POST http://localhost:5555/api/v1/local/session \
  -H "Authorization: Bearer test" -H "Content-Type: application/json" \
  -d @"$PB_DIR/session.json" > "$CORAL_WS/session-response.json"
log "session created: $(head -c 300 "$CORAL_WS/session-response.json" | tr '\n' ' ')"

next_snap=$SNAP_MIN
tick=0
while :; do
  sleep 10; tick=$((tick + 1))
  now=$(date +%s)
  el=$(( now - START ))
  if [ "$el" -ge $(( next_snap * 60 )) ] && [ "$next_snap" -lt "$BUDGET_MIN" ]; then
    snapshot "$(printf 't%03d' "$next_snap")"; next_snap=$((next_snap + SNAP_MIN)); dump_state
  fi
  if [ $((tick % 6)) -eq 0 ]; then
    sync_logs
    log "$((el/60)) min | claude procs: $(pgrep -fc 'claude --verbose' || true) | server log lines: $(wc -l < "$CORAL_WS/coral-server.log" 2>/dev/null || echo 0)"
  fi
  [ "$now" -ge "$DEADLINE" ] && break
done

log "deadline reached: stopping the team"
touch "$PB_DIR/STOP"
pkill -TERM -f 'claude --verbose' 2>/dev/null || true
sleep 15
pkill -KILL -f 'claude --verbose' 2>/dev/null || true
snapshot "$(printf 't%03d-final' "$BUDGET_MIN")"
sync_logs; dump_state
cp /tmp/coral-session-dumps/*.json "$OUT/coral-state/" 2>/dev/null || true
git -C "$WS_DIR" log --format='%ad %an %s' --date=format:'%H:%M:%S' 2>/dev/null | head -300 > "$OUT/git-log.txt"
git -C "$WS_DIR" shortlog -sn HEAD < /dev/null 2>/dev/null > "$OUT/git-authors.txt" || true
pkill -TERM -f 'coral-server.jar' 2>/dev/null || true
log "done total=$(( $(date +%s) - START ))s"
ls -la "$SNAPS" >> "$RUNLOG"
exit 0
