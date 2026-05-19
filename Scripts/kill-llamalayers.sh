#!/usr/bin/env bash
# kill-llamalayers.sh — one-shot Metal / llama.cpp process scrubber.
#
# Usage:
#   bash Scripts/kill-llamalayers.sh       # normal kill
#   bash Scripts/kill-llamalayers.sh --hard # SIGKILL everything matching llama-server
#
# Side-effect: empties port 11345 by killing every listener PID.
# Safe to run whether or not Keybreeze is currently active.

set -euo pipefail

MODE="${1:---soft}"
LLAMA_PATTERN="/opt/homebrew/bin/llama-server"

echo "🔪  Scrubbing llama-server / Metal resource layer…"

if [[ "$MODE" == "--hard" ]]; then
    echo "  → SIGKILL mode"
    /usr/bin/pkill -9 -f "$LLAMA_PATTERN" || true
else
    echo "  → SIGTERM → wait → SIGKILL escalation"
    /usr/bin/pkill -f "$LLAMA_PATTERN" || true
    sleep 1
    /usr/bin/pkill -9 -f "$LLAMA_PATTERN" || true
fi

# Port sweep: kill anything still holding 11345 after the process kill
if /usr/sbin/lsof -ti tcp:11345 >/dev/null 2>&1; then
    echo "  → Port 11345 still occupied — removing remaining holders"
    while read -r pid; do
        [[ "$pid" -gt 1 ]] && kill -9 "$pid" 2>/dev/null || true
    done < <(/usr/sbin/lsof -ti tcp:11345)
    sleep 0.2
fi

echo "✅  Clean."
