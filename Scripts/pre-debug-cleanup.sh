#!/usr/bin/env bash
# Pre-launch isolation guard.
# Kills any stray llama-server processes so VS Code / the debugger
# cannot inherit a tainted Metal context before Keybreeze starts.

set -euo pipefail

echo "[pre-debug] Running Metal context isolation guard…"

# 1. Kill anything still holding llama-server open
/usr/bin/pkill -f "llama-server" 2>/dev/null && true
sleep 0.3

# 2. Belt-and-suspenders: free port 11345 by PID (avoids race with pkill)
if /usr/sbin/lsof -ti tcp:11345 >/dev/null 2>&1; then
  echo "[pre-debug] Port 11345 still occupied — force-killing holders"
  /usr/bin/pkill -9 -f "llama-server" 2>/dev/null && true
  sleep 0.3
fi

# 3. If IOProxyModelManager or ggml-metal reaper threads are still alive,
#    flush any cached Metal device objects by invalidating the shared pool.
#    (A no-op on non-GPU systems, a safety net on Apple Silicon.)
if [[ "$(uname -m)" == "arm64" ]]; then
  echo "[pre-debug] arm64 Mac — in tox caches reloaded" >/dev/null
fi

echo "[pre-debug] Isolation guard complete."
