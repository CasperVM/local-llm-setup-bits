#!/usr/bin/env bash
# Kill stale llama-server processes and reclaim VRAM + RAM.
# Usage: ./free-resources.sh [--restart <script-in-scripts-dir>]
#   --restart run-nvidia.sh   optionally restart the server after cleanup
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTART_SCRIPT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --restart) RESTART_SCRIPT="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

hr() { printf '%*s\n' 60 '' | tr ' ' '-'; }

echo_stat() {
    local label="$1"
    echo "[$label]"
    echo "  VRAM: $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits 2>/dev/null \
        | awk -F', ' '{printf "used=%sMiB  free=%sMiB", $1, $2}')"
    echo "  RAM:  $(free -h | awk '/^Mem:/{printf "used=%s  free=%s  cache=%s", $3, $4, $6}')"
}

hr; echo_stat "BEFORE"; hr

PIDS=$(pgrep -f 'llama-server' 2>/dev/null || true)
if [[ -n "$PIDS" ]]; then
    echo "Stopping llama-server PIDs: $PIDS"
    kill -TERM $PIDS 2>/dev/null || true
    sleep 3
    PIDS_STILL=$(pgrep -f 'llama-server' 2>/dev/null || true)
    if [[ -n "$PIDS_STILL" ]]; then
        echo "Force-killing: $PIDS_STILL"
        kill -KILL $PIDS_STILL 2>/dev/null || true
    fi
    echo "llama-server stopped."
else
    echo "No llama-server process found."
fi

if sudo -n true 2>/dev/null; then
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    echo "Page cache dropped."
else
    echo "Skipping page cache drop (no passwordless sudo)."
    echo "  Run manually: sync && echo 3 | sudo tee /proc/sys/vm/drop_caches"
fi

sleep 2
hr; echo_stat "AFTER"; hr

if [[ -n "$RESTART_SCRIPT" ]]; then
    FULL_PATH="$SCRIPT_DIR/$RESTART_SCRIPT"
    [[ ! -f "$FULL_PATH" ]] && { echo "Restart script not found: $FULL_PATH"; exit 1; }
    echo "Restarting: $RESTART_SCRIPT"
    exec bash "$FULL_PATH"
fi
