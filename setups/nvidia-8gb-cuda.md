# Small NVIDIA GPU (~7–8 GB, CUDA)

> ⚠️ **DRAFT — not yet verified on real hardware.** The numbers below are *predicted*
> from the larger-GPU profile, not measured. Treat `--n-cpu-moe` as a starting point to
> tune. This page will be finished once it's been tested on an ~8 GB card.

Running the MoE model on a consumer NVIDIA card with ~7–8 GB of VRAM. The model is ~22 GB,
so most expert layers live in **system RAM** (CPU) and only a slice fits on the GPU —
hence the **≥16 GB free RAM** requirement.

---

## Setup is the same as the larger-NVIDIA profile

Build and CUDA setup are identical — follow these from
[`nvidia-16gb-cuda.md`](nvidia-16gb-cuda.md):

1. **CUDA toolkit** — Step 1 (avoid the too-old apt CUDA; install a version matching your
   driver from NVIDIA's repo).
2. **Build llama.cpp** — Step 2 (`-DGGML_CUDA=ON`).
3. **Download the model** — [`../guides/01-download-model.md`](../guides/01-download-model.md).

---

## What's different: push more experts to the CPU

With only ~8 GB VRAM, far fewer expert layers fit on the GPU. Raise `--n-cpu-moe`
substantially and drop the parallel slots:

```bash
./llama.cpp/build/bin/llama-server \
    -m models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf \
    -a qwen3.6-35b \
    -ngl 99 --n-cpu-moe 34 -c 16384 \
    --no-mmap --mlock \
    --cache-type-k q4_0 --cache-type-v q4_0 \
    --flash-attn auto \
    --host 0.0.0.0 --port 8080 \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0
```

**How to tune `--n-cpu-moe` (TODO: replace with measured values):**

- Start high (e.g. `34`–`36` of 48 experts on CPU) so it fits.
- Watch VRAM with `nvidia-smi`. If you have headroom, **lower** the number a few at a time
  (more experts on GPU = faster) until VRAM is ~90% full or it OOMs.
- Smaller context (`-c 16384`) also frees VRAM; raise it if you have room.
- Expect this profile to be **slower** than the 15 GB+ card — most of the model is running
  on the CPU.

---

## Next steps

- Always-on service → [`../guides/02-run-as-server.md`](../guides/02-run-as-server.md)
- Connect opencode → [`../guides/03-connect-opencode.md`](../guides/03-connect-opencode.md)

---

### Help finish this page

If you've run this on a real ~8 GB card, the useful data to contribute: the highest
`--n-cpu-moe` that still fits, the resulting tokens/sec, and peak VRAM use.
