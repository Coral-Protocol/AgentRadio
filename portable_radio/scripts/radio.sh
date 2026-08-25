#!/bin/sh
# portable_radio — a dependency-free file-backed implementation of the three
# AgentRadio primitives (create_thread / send_message / wait_for_mention).
#
# It replaces the Coral message server (coral-server.jar + JDK + Docker) with an
# append-only JSONL directory, so any agent that can run shell commands can join
# a passive-awareness team. See SKILL.md for the collaboration protocol.
#
# Usage:
#   radio.sh init [--root DIR]
#   radio.sh send <thread> <from> <content> [--mentions agent-2,agent-3]
#   radio.sh wait <me> [--root DIR] [--max-wait SEC] [--max-rounds N]
#   radio.sh read  [--root DIR]
#   radio.sh threads [--root DIR]
#
# The radio root defaults to $RADIO_ROOT or ./.radio.
# Requires python3 (stdlib only), same dependency as upstream passive_scripts.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$DIR/radio_main.py" "$@"
