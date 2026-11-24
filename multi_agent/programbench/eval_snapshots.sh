#!/usr/bin/env bash
# Stage every snapshot of a finished Pier job as its own programbench run dir and grade
# them all with the official evaluator (works for 40- and 60-minute runs).
#   usage: PB_REPO=<programbench checkout> bash eval_snapshots.sh <task> <instance_id> <pier_trial_dir> <out_dir> [workers] [branch_workers] [docker_cpus]
#   e.g.   bash eval_snapshots.sh pandoc jgm__pandoc.5caad90 jobs/pb-l3-local-pandoc-40m-01/pandoc__XXXX /data/pbgrade/pandoc-l3 5 2 3
# Afterwards: cd $PB_REPO && uv run python <this dir>/curve.py <out_dir> <instance_id>
set -euo pipefail
TASK=$1; IID=$2; TRIAL=$3; OUT=$4; W=${5:-3}; B=${6:-2}; CPUS=${7:-4}
PB_REPO="${PB_REPO:?set PB_REPO to the programbench checkout (programbench eval, reruns-delay patched to 0)}"
mkdir -p "$OUT"
dirs=()
# every snapshot present except t000, the final one first
ORDER="$(ls "$TRIAL"/agent/snapshots/t*-final.tar.gz "$TRIAL"/agent/snapshots/t0[0-9][0-9].tar.gz 2>/dev/null | xargs -n1 basename | sed 's/\.tar\.gz$//' | grep -v '^t000$' | tr '\n' ' ')"
for snap in $ORDER; do f="$TRIAL/agent/snapshots/$snap.tar.gz"; [ -f "$f" ] || continue
  d="$OUT/$snap/$IID"; mkdir -p "$d"
  [ -f "$d/submission.tar.gz" ] || cp "$f" "$d/submission.tar.gz"
  dirs+=("$OUT/$snap")
done
echo "staged ${#dirs[@]} snapshots under $OUT: $ORDER"
cd "$PB_REPO"
uv run programbench eval "${dirs[@]}" -w "$W" -b "$B" --docker-cpus "$CPUS" 2>&1 | grep -v "Fetching\|Evaluating:" || true
