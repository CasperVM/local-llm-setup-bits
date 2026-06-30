#!/usr/bin/env bash
# Run the MoE model on an NVIDIA GPU via llama.cpp + CUDA.
# Full guide: ../setups/nvidia-16gb-cuda.md (or nvidia-8gb-cuda.md for smaller cards)
#
# Tuned for a ~15 GB card + ample system RAM. For a ~7-8 GB card, raise --n-cpu-moe
# (more experts on CPU). Listens on 0.0.0.0 for network access -- only do this on a
# trusted network.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="$DIR/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"
SERVER="$DIR/llama.cpp/build/bin/llama-server"

[[ -f "$MODEL" ]]  || { echo "model not found: $MODEL (see guides/01-download-model.md)"; exit 1; }
[[ -x "$SERVER" ]] || { echo "server not built: $SERVER (see setups/nvidia-16gb-cuda.md)"; exit 1; }

# Free VRAM/RAM and kill any stale instance before starting (no-op if nothing is running).
"$DIR/scripts/free-resources.sh"

exec "$SERVER" \
    -m "$MODEL" \
    -a qwen3.6-35b \
    -ngl 99 \
    --n-cpu-moe 20 \
    -np 2 \
    -c 49152 \
    --no-mmap \
    --mlock \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --flash-attn auto \
    --presence-penalty 1.5 \
    --host 0.0.0.0 --port 8080 \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0 \
    "$@"

# --n-cpu-moe: experts forced onto CPU. ~15 GB VRAM -> 20 works well. ~8 GB VRAM -> try
# 30-36 (more on CPU). --mlock needs RLIMIT_MEMLOCK=unlimited (systemd unit sets it; for a
# manual run do `ulimit -l unlimited` first). KV cache quantized to q4_0 to save VRAM.
