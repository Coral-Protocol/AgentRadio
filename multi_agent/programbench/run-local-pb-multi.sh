#!/usr/bin/env bash
# One ProgramBench task, 4-agent team (L3 share-as-you-go with a watcher, L3H share-as-you-go
# with hook-delivered receive, or L2.5p windows + share-as-you-go working phases), on LOCAL Docker.
#   usage: VARIANT=l3|l3h|l25p TASK=pandoc BUDGET_MIN=40 bash run-local-pb-multi.sh
# Token: CLAUDE_CODE_OAUTH_TOKEN env, else ~/.claude/oauth-token, else the current session
# token from ~/.claude/.credentials.json (short-lived; must outlive the run).
set -euo pipefail
cd /home/xinxing/deep-swe

VARIANT="${VARIANT:-l3}"
TASK="${TASK:-pandoc}"
MODEL="${MODEL:-anthropic/claude-opus-5-5}"
EFFORT="${EFFORT:-xhigh}"
BUDGET_MIN="${BUDGET_MIN:-40}"
SNAP_MIN="${SNAP_MIN:-5}"
CPUS="${CPUS:-8}"
MEM_MB="${MEM_MB:-16384}"
JOB_NAME="${JOB_NAME:-pb-${VARIANT}-local-${TASK}-${BUDGET_MIN}m-01}"
case "$VARIANT" in
  l3)  CLS=ProgramBenchCoralL3 ;;
  l3h) CLS=ProgramBenchCoralL3H ;;
  l25p) CLS=ProgramBenchCoralL25P ;;
  *) echo "VARIANT must be l3|l3h|l25p" >&2; exit 1 ;;
esac

if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  if [[ -s "$HOME/.claude/oauth-token" ]]; then
    CLAUDE_CODE_OAUTH_TOKEN="$(tr -d '[:space:]' < "$HOME/.claude/oauth-token")"
  else
    CLAUDE_CODE_OAUTH_TOKEN="$(python3 -I -c "import json;print(json.load(open('$HOME/.claude/.credentials.json'))['claudeAiOauth']['accessToken'])")"
    echo ">>> using the current session token from .credentials.json" >&2
  fi
fi
export CLAUDE_CODE_OAUTH_TOKEN

if [[ -d "jobs/$JOB_NAME" ]]; then echo "jobs/$JOB_NAME exists; set JOB_NAME" >&2; exit 1; fi

exec env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL -u ANTHROPIC_MODEL \
  PYTHONPATH=/home/xinxing/deep-swe \
  /home/xinxing/.local/bin/pier run \
  -p pb_tasks -i "$TASK" --n-tasks 1 -n 1 --n-attempts 1 --max-retries 0 \
  --agent-import-path "pb_agent.pb_multi_agent:$CLS" \
  --model "$MODEL" \
  --ak budget_minutes="$BUDGET_MIN" --ak snapshot_minutes="$SNAP_MIN" --ak effort="$EFFORT" \
  --env docker \
  --override-cpus "$CPUS" --override-memory-mb "$MEM_MB" \
  --job-name "$JOB_NAME" "$@"
