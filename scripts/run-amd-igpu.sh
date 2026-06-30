#!/usr/bin/env bash
# Run the MoE model on an AMD integrated GPU (RDNA3) via llama.cpp + ROCm.
# Full guide: ../setups/amd-igpu-rocm.md
#
# Default profile: --n-cpu-moe 12 -- 12 of the 48 MoE expert layers stay on the CPU,
# the other 36 run on the iGPU. The sweet spot: fast on normal prompts AND stable on
# large ones. Faster than 99, without the GPU-hang landmine of 0.
# Listens on localhost only -- change --host to 0.0.0.0 for network access.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="$DIR/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"
SERVER="$DIR/llama.cpp/build/bin/llama-server"

[[ -f "$MODEL" ]]  || { echo "model not found: $MODEL (see guides/01-download-model.md)"; exit 1; }
[[ -x "$SERVER" ]] || { echo "server not built: $SERVER (see setups/amd-igpu-rocm.md)"; exit 1; }

# RDNA3 iGPUs (e.g. gfx1103) hang on prefill with their native rocBLAS kernels. The build
# targets gfx1100; this override routes the whole stack through that stable code path.
# Do NOT remove it. Adjust the value to match the arch you built for.
export HSA_OVERRIDE_GFX_VERSION=11.0.0

exec "$SERVER" \
    -m "$MODEL" \
    -a qwen3.6-35b \
    -ngl 99 \
    --n-cpu-moe 12 \
    -fa 0 \
    -c 32768 \
    --host 127.0.0.1 --port 8080 \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0 \
    "$@"

# --n-cpu-moe tradeoff (measured on a Radeon 780M):
#    0 = all experts on iGPU : ~17 t/s  -- fastest, but HANGS on large prefills. Don't use.
#   12 = 36 experts on iGPU  : ~12 t/s  -- stable even under an 8.5K-token stress prompt. <-DEFAULT
#   99 = all experts on CPU  : ~7  t/s  -- bombproof but sluggish.
