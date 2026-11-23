#!/usr/bin/env bash
# One DeepSWE task with the 4-agent message-server team on Modal (Claude subscription).
#   usage: VARIANT=l2|l3|l1|l25 TASK=ipython-session-bundle-replay bash run-modal-multiagent-one.sh
# Token: CLAUDE_CODE_OAUTH_TOKEN env, else ~/.claude/oauth-token, else the current session
# token from ~/.claude/.credentials.json (short-lived; fine for a single run).
set -euo pipefail
cd /home/xinxing/deep-swe

VARIANT="${VARIANT:-l2}"
TASK="${TASK:-ipython-session-bundle-replay}"
MODEL="${MODEL:-anthropic/claude-opus-4-6}"
CPUS="${CPUS:-4}"
MEM_MB="${MEM_MB:-16384}"
JOB_NAME="${JOB_NAME:-deepswe-${VARIANT}-${TASK%%-*}-01}"
case "$VARIANT" in
  l1) CLS=CoralMultiAgentDeepSWEL1 ;;
  l2) CLS=CoralMultiAgentDeepSWEL2 ;;
  l3) CLS=CoralMultiAgentDeepSWEL3 ;;
  l25) CLS=CoralMultiAgentDeepSWEL25 ;;
  *) echo "VARIANT must be l1|l2|l3|l25" >&2; exit 1 ;;
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
  MODAL_PROFILE=renxinxing1 \
  /home/xinxing/.local/bin/pier run \
  -p tasks -i "$TASK" --n-tasks 1 -n 1 --n-attempts 1 --max-retries 0 \
  --agent-import-path "multi_agent.coral_multi_agent_deepswe:$CLS" \
  --model "$MODEL" \
  --env modal --ek app_name="deepswe-${VARIANT}-multiagent" \
  --override-cpus "$CPUS" --override-memory-mb "$MEM_MB" \
  --job-name "$JOB_NAME" "$@"
