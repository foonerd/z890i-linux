#!/bin/bash
# Run an X client against a throwaway Xwayland server so a server crash cannot take the session down.
# Usage: ./test-on-disposable-xwayland.sh [path/to/Xwayland] [client command...]
# Default: the installed /usr/bin/Xwayland and "conky -c ~/.conkyrc". Exit 0 = server survived the client.
set -u
XW=${1:-/usr/bin/Xwayland}; shift 2>/dev/null; CLIENT=("$@"); [ ${#CLIENT[@]} -gt 0 ] || CLIENT=(conky -c "$HOME/.conkyrc")
LOG=$(mktemp); "$XW" :3 -rootless -noreset >"$LOG" 2>&1 & PID=$!
for i in $(seq 1 20); do xrandr -display :3 -q >/dev/null 2>&1 && break; sleep 0.5; done
DISPLAY=:3 timeout 8 "${CLIENT[@]}" >/dev/null 2>&1; sleep 1
if kill -0 "$PID" 2>/dev/null; then echo "OK: $XW survived ${CLIENT[*]}"; rc=0; else echo "CRASH: $XW died running ${CLIENT[*]}"; grep -E 'Segmentation|Fatal server' "$LOG"; rc=1; fi
kill "$PID" 2>/dev/null; rm -f "$LOG"; exit $rc
