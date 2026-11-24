#!/bin/bash
# Bell timer for ProgramBench team runs. Sleeps until the next scheduled bell,
# prints it, and exits. Agents keep exactly one of these running as a background
# task and relaunch it after each bell. Bells are the harness clock only.
#   files: /tmp/pb/start_epoch (unix seconds when the team was started)
#          /tmp/pb/bells.txt   (lines: <minute><TAB><text>)
PB_DIR="${PB_DIR:-/tmp/pb}"
START=$(cat "$PB_DIR/start_epoch" 2>/dev/null) || { echo "bell: no start_epoch yet"; exit 1; }
now() { date +%s; }
elapsed=$(( $(now) - START ))
next_min=""; next_text=""
while IFS=$'\t' read -r m t; do
  [ -z "$m" ] && continue
  if [ $(( m * 60 )) -gt "$elapsed" ]; then next_min="$m"; next_text="$t"; break; fi
done < "$PB_DIR/bells.txt"
if [ -z "$next_min" ]; then
  echo "BELL: no bells left (elapsed $((elapsed/60)) min). The deadline will end the run."; exit 0
fi
sleep $(( next_min * 60 - elapsed ))
el=$(( $(now) - START ))
printf 'BELL [%02d:%02d] %s\n' $((el/60)) $((el%60)) "$next_text"
echo "remaining bells:"
while IFS=$'\t' read -r m t; do [ -n "$m" ] && [ "$m" -gt "$next_min" ] && printf '  %3d  %s\n' "$m" "$t"; done < "$PB_DIR/bells.txt"
exit 0
