# local-llm-setup-bits

Ready-to-follow guides for running a local **Mixture-of-Experts (MoE) LLM** on your
own hardware with [llama.cpp](https://github.com/ggml-org/llama.cpp), plus connecting
it to the [opencode](https://opencode.ai/) coding agent.

Every guide is a **read-and-run checklist**: short bullet points and copy-paste blocks
you execute one at a time. No magic scripts you have to trust blindly — the helper
scripts in [`scripts/`](scripts/) just bundle commands the guides already explain.

All profiles serve the **same model** by default (`Qwen3.6-35B-A3B`, a ~35B MoE with
~3B active params, in Q4_K_M GGUF — ~22 GB on disk). The model is swappable; see
[`guides/01-download-model.md`](guides/01-download-model.md).

> **Pinned build:** the guides build llama.cpp at tag **`b9843`** (commit `86b9470`) —
> the release these configs were tested against, so your build matches the tuning notes.
> Newer versions usually work too, but pin this if something misbehaves.

---

## How it works (the 30-second version)

- **MoE = cheap to run, big to store.** Only a few "expert" layers fire per token, so a
  35B model runs at small-model speed — *if* you can fit it in memory.
- The lever on every machine is **`--n-cpu-moe`**: how many expert layers stay on the
  **CPU** (system RAM) instead of the **GPU** (VRAM). More on CPU = fits in less VRAM but
  slower. Each profile below ships a tuned default.
- You need roughly **`model size − VRAM`** of free system RAM for the experts that don't
  fit on the GPU. For the default ~22 GB model that means **≥16 GB free RAM** on the
  small-GPU profiles.

---

## Pick your hardware

| Profile | GPU | Free RAM | Backend | Guide |
|---|---|---|---|---|
| **AMD integrated GPU** | Radeon iGPU (RDNA3, e.g. 780M), shared memory | a lot (model lives in shared RAM/GTT) | ROCm / HIP | [`setups/amd-igpu-rocm.md`](setups/amd-igpu-rocm.md) |
| **Small NVIDIA GPU** | ~7–8 GB VRAM | ≥16 GB | CUDA | [`setups/nvidia-8gb-cuda.md`](setups/nvidia-8gb-cuda.md) — *verified on RTX 3070* |
| **Larger NVIDIA GPU** | ~15 GB+ VRAM (server-class) | ≥16 GB | CUDA | [`setups/nvidia-16gb-cuda.md`](setups/nvidia-16gb-cuda.md) |

Don't see your exact card? Pick the closest profile and adjust `--n-cpu-moe` — the setup
guides explain how to tune it.

---

## Shared steps (used by every profile)

The hardware guides send you here at the right moment so each step lives in one place:

1. [`guides/01-download-model.md`](guides/01-download-model.md) — get the GGUF model (and how to swap models)
2. [`guides/02-run-as-server.md`](guides/02-run-as-server.md) — run it always-on as a `systemd` service that auto-restarts
3. [`guides/03-connect-opencode.md`](guides/03-connect-opencode.md) — drive it from the opencode agent, locally or over the network

---

## Repository layout

```
README.md            this index
setups/              one guide per hardware profile (start here)
guides/              shared steps the setup guides link into
scripts/             helper scripts + config templates the guides reference
```

---

## A few honest caveats

- This is **a very smart autocomplete**, not a knowledge base. It makes mistakes. Review
  everything it produces, especially before running commands.
- It runs **on whatever machine you point it at**. The output is your responsibility.
- These are personal, hands-on notes — tuning numbers (tok/s, offload counts) were
  measured on specific hardware and are starting points, not guarantees.

## License

[MIT](LICENSE).
