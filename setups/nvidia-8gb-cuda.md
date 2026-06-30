# Small NVIDIA GPU (~7–8 GB, CUDA)

Running the MoE model on a consumer NVIDIA card with ~7–8 GB of VRAM. The model is ~22 GB,
so most expert layers live in **system RAM** (CPU) and only a slice + the attention layers
fit on the GPU — hence the **≥16 GB free RAM** requirement (32 GB comfortable).

> **Verified machine:** NVIDIA RTX 3070 (8 GB) + Ryzen 5 5600X (6c/12t) + 32 GB RAM,
> Fedora 44. Measured on `Qwen3.6-35B-A3B` Q4_K_M: **prefill ~600 tok/s, generation
> ~42–45 tok/s** at 131K context. Snappy for an 8 GB card.

---

## Step 1 — Get CUDA (conda is the easy path here)

You need a CUDA toolkit newer than what most distros ship. The 16 GB guide installs it
from NVIDIA's apt repo; on this 8 GB box the **conda-forge** route proved simplest and
fully self-contained (no root, no system-toolkit conflicts):

```bash
# install miniconda if you don't have it, then:
conda create -n llama-cuda -c conda-forge -c nvidia \
    cuda-nvcc cuda-cudart-dev cuda-nvrtc gcc gxx
conda activate llama-cuda
nvcc --version    # should report CUDA 12.x
```

- This pulls the compiler (`cuda-nvcc`) and runtime (`cuda-cudart`) into the env only.
- Confirm your driver supports CUDA 12.x: `nvidia-smi` (top-right CUDA version).
- Prefer the system toolkit instead? Follow Step 1 of
  [`nvidia-16gb-cuda.md`](nvidia-16gb-cuda.md) — both work.

---

## Step 2 — Build llama.cpp (CUDA)

With the conda env active so `nvcc` and the CUDA libs are on the path:

```bash
# pinned to the release these configs were tested against (tag b9843 == 86b9470)
git clone --depth 1 --branch b9843 https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
./build/bin/llama-server --version    # smoke test
```

- CUDA arch (`860` for the RTX 3070, SM 8.6) is auto-detected — no manual flag needed.
- The build links against the conda env's CUDA libs, so the **run script must expose
  them at runtime** via `LD_LIBRARY_PATH` (handled below).

---

## Step 3 — Download the model

→ **[`../guides/01-download-model.md`](../guides/01-download-model.md)**. Come back when done.

> **Tight on VRAM/RAM?** A lighter MoE like `Qwen3-30B-A3B-Instruct-2507` Q4_K_M (~18.6 GB)
> also runs well here and leaves more headroom. Same flags, just a different `-m` path.

---

## Step 4 — Run it

```bash
ulimit -l unlimited          # required for --mlock
./scripts/run-nvidia-8gb.sh
```

If you built CUDA via conda (Step 1), **uncomment the `LD_LIBRARY_PATH` line** in
`scripts/run-nvidia-8gb.sh` and point it at your env (`~/miniconda3/envs/llama-cuda/lib`).

Or run directly:

```bash
export LD_LIBRARY_PATH="$HOME/miniconda3/envs/llama-cuda/lib:$LD_LIBRARY_PATH"  # conda builds only
ulimit -l unlimited
./llama.cpp/build/bin/llama-server \
    -m models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf \
    -a qwen3.6-35b \
    -ngl 99 --n-cpu-moe 34 -np 1 -c 131072 \
    --no-mmap --mlock \
    --cache-type-k q4_0 --cache-type-v q4_0 \
    --flash-attn auto \
    --host 0.0.0.0 --port 8080 \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0
```

What the 8 GB-specific flags do:

- `-ngl 99 --n-cpu-moe 34` — push everything to GPU, then pull 34 of 48 expert layers back
  to CPU RAM. This pair is the whole game on a small card.
- `-np 1` — single request slot. Drops the compute buffer from ~533 MB to ~133 MB of
  precious VRAM. Raise to 2–4 only if you need concurrent requests.
- `--no-mmap --mlock` — load the model fully into RAM and pin it, so experts don't get
  swapped out after hours of uptime (the "day-3 slowdown"). Needs `ulimit -l unlimited`.
- `--cache-type-k/v q4_0` — 4-bit KV cache, ~50% smaller than q8_0; lets you keep a big
  context in 8 GB.
- `--flash-attn auto` — fine on NVIDIA, saves memory.

---

## Tuning `--n-cpu-moe` (watch `nvidia-smi`)

`34` is the verified default for the 35B model at 131K context. Adjust to your card:

| Symptom | Action |
|---|---|
| VRAM has **< 500 MB free** or it OOMs | **raise** `--n-cpu-moe` (e.g. 36, 38) — more experts on CPU |
| VRAM has **> 1.5 GB free** | **lower** it (e.g. 32, 30) — more experts on GPU = faster |
| Context too small for your use | raise `-c` *after* confirming VRAM headroom |

Generation speed tracks how many experts land on the GPU, so the goal is to fill VRAM
without spilling. Expect this profile to be slower than the 15 GB+ card — most of the
model runs on the CPU.

---

## Next steps

- Always-on service → [`../guides/02-run-as-server.md`](../guides/02-run-as-server.md)
  (set `ExecStart` to `run-nvidia-8gb.sh`, and add the conda `LD_LIBRARY_PATH` to the unit
  via `Environment=` if you built with conda)
- Connect opencode → [`../guides/03-connect-opencode.md`](../guides/03-connect-opencode.md)

---

> **`Qwen3.6` is a reasoning model** — it emits a long `<think>` block first. Give clients
> a generous `max_tokens` (200+) or short answers come back empty.
