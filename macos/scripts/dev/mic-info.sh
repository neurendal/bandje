#!/usr/bin/env bash
# Diagnostics for the default input device: lid state (built-in mic is off in clamshell)
# and the audio hardware overview. Read-only.
set -uo pipefail
echo "== clamshell =="
ioreg -r -k AppleClamshellState -d 1 | grep -E 'AppleClamshell(State|CausesSleep)' || echo "no clamshell info"
echo "== input devices =="
system_profiler SPAudioDataType | grep -B2 -A8 'Input Channels' | grep -vE '^\s*$'
