#!/usr/bin/env bash
# Run the MoE model on a small (~8 GB) NVIDIA GPU via llama.cpp + CUDA.
# Full guide: ../setups/nvidia-8gb-cuda.md
#
# Verified on: RTX 3070 (8 GB) + Ryzen 5 5600X (6c/12t) + 32 GB RAM.
# Measured: prefill ~600 tok/s, generation ~42-45 tok/s (Qwen3.6-35B-A3B Q4_K_M).
#
# IMPORTANT: --mlock needs RLIMIT_MEMLOCK=unlimited. Run this first in your shell:
#   ulimit -l unlimited
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="$DIR/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"
SERVER="$DIR/llama.cpp/build/bin/llama-server"

# If you built CUDA from a conda env (see the guide), expose its libs at runtime.
# Uncomment and point at your env:
# export LD_LIBRARY_PATH="$HOME/miniconda3/envs/llama-cuda/lib:${LD_LIBRARY_PATH:-}"

[[ -f "$MODEL" ]]  || { echo "model not found: $MODEL (see guides/01-download-model.md)"; exit 1; }
[[ -x "$SERVER" ]] || { echo "server not built: $SERVER (see setups/nvidia-8gb-cuda.md)"; exit 1; }

# Free VRAM/RAM and kill any stale instance first (no-op if nothing is running).
"$DIR/scripts/free-resources.sh"

exec "$SERVER" \
    -m "$MODEL" \
    -a qwen3.6-35b \
    -ngl 99 \
    --n-cpu-moe 34 \
    -np 1 \
    -c 131072 \
    --no-mmap \
    --mlock \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --flash-attn auto \
    --host 0.0.0.0 --port 8080 \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0 \
    "$@"

# Tuning --n-cpu-moe on 8 GB (watch `nvidia-smi`):
#   34 = most experts on CPU : fits with ~131K ctx + room to spare.  <-DEFAULT
#   lower it a few at a time if VRAM has >1.5 GB free (more on GPU = faster).
#   raise it if VRAM has <500 MB free or you OOM.
# -np 1 keeps the compute buffer small (~133 MB vs ~533 MB at -np 4); raise only
# if you need concurrent requests.
