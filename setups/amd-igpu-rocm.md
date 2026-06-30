# AMD integrated GPU (ROCm)

Running the MoE model on an **AMD Radeon integrated GPU** (RDNA3, e.g. the 780M) via
llama.cpp's ROCm/HIP backend.

> **Reference machine:** AMD Ryzen 9 7940HS + Radeon 780M iGPU (RDNA3, `gfx1103`), 54 GiB
> RAM, Fedora 44. Verified working. Your mileage varies with RAM and APU generation.

An iGPU has **no dedicated VRAM** — it shares system memory. That changes the rules: you
won't run out of "VRAM" the way a discrete card does, but you *will* fight the desktop
compositor for the small shared display pool unless you set things up right. This guide
covers those gotchas.

---

## Is your GPU supported by ROCm?

- ROCm officially supports a limited list of GPUs. Check AMD's compatibility matrix
  first: **<https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html>**
- **Many consumer iGPUs (like `gfx1103`) are *not* on the official list but work
  unofficially** by pretending to be a supported sibling (see the override trick below).
- Find your GPU's `gfxNNNN` architecture id with `rocminfo | grep gfx` after installing
  ROCm, or look it up from your APU model.

---

## Step 1 — Install ROCm

On Fedora 44, ROCm 7.x ships in the distro repos (no AMD repo needed). On other distros,
follow AMD's installer from the link above.

- Install the **runtime + tools** (enough to *run* workloads):

  ```bash
  sudo dnf install -y rocminfo rocm-smi rocm-opencl clinfo rocm-hip rocblas hipcc
  ```

- Install the **dev headers** (needed to *compile* llama.cpp's ROCm backend):

  ```bash
  sudo dnf install -y rocm-hip-devel rocblas-devel hipblas-devel opencl-headers
  ```

- Verify the GPU is seen:

  ```bash
  rocminfo | grep -E 'Name|gfx'   # should list your gfxNNNN compute agent
  clinfo | grep -i 'device name'
  ```

> `rocm-smi` may throw a harmless `map::at` / "low-power state" warning on APUs (no
> power-cap sysfs on integrated parts). Detection still works.

---

## Step 2 — The override that makes unsupported iGPUs work

The 780M is `gfx1103`. Its **native rocBLAS kernels hang the GPU on prompt processing**
(`HW Exception ... GPU Hang`). The fix is to build and run against `gfx1100` — also
RDNA3, binary-compatible, and stable:

```bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0   # treat gfx1103 as the stable gfx1100
```

- You'll pass this when **building** (target `gfx1100`) and **running** (the run script
  exports it for you).
- **The override only works because the binary is built for `gfx1100`.** Using it against
  a `gfx1103`-only build *segfaults* (no matching code object).
- Adjust the target/override for your APU: the rule is "build for, and override to, the
  nearest officially-supported RDNA3 arch."

---

## Step 3 — Build llama.cpp for `gfx1100`

```bash
# get the source, pinned to the release these configs were built & tested against.
# tag b9843 == commit 86b94708f22478f900b76ca02e316f4f3418faff
git clone --depth 1 --branch b9843 https://github.com/ggml-org/llama.cpp.git
cd llama.cpp

# build the HIP backend, targeting gfx1100 (NOT native gfx1103)
HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
  cmake -S . -B build -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1100 \
  -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF
cmake --build build -j"$(nproc)"

./build/bin/llama-server --version   # smoke test
```

> **Why `gfx1100` + override, not native `gfx1103`:** native generation alone worked
> (~7 t/s) but any real prompt processing wedged the GPU. Building for `gfx1100` routes
> both llama.cpp's kernels *and* rocBLAS through the stable path — no hangs, generation
> roughly doubled.

---

## Step 4 — Download the model

Get the GGUF now → **[`../guides/01-download-model.md`](../guides/01-download-model.md)**.
Come back here when it's downloaded.

---

## Step 5 — Raise the GTT ceiling (so the iGPU can borrow more RAM)

The model's expert tensors spill into **GTT** (system RAM the GPU borrows) — *not* the
small display pool. GTT is the real ceiling for how much you can offload. The default
limit is often too low (~27 GiB on the reference box). Raise it once (persists across
boots):

```bash
# 10485760 pages × 4 KiB = 40 GiB. Leave system headroom — don't hand over all your RAM.
sudo grubby --update-kernel=ALL --args="ttm.pages_limit=10485760 ttm.page_pool_size=10485760"
# then reboot
```

- `ttm.pages_limit` is the current knob; the older `amdgpu.gttsize` is deprecated.
- On non-`grubby` distros, add the same `ttm.pages_limit=... ttm.page_pool_size=...` to
  your kernel cmdline (GRUB config) and update-grub.
- Verify after reboot:

  ```bash
  grep -o 'ttm.pages_limit=[0-9]*' /proc/cmdline
  cat /sys/class/drm/card*/device/mem_info_gtt_total   # → 42949672960 (40 GiB)
  ```

---

## Step 6 — Run it

Use the helper script (it exports the override and sane sampling defaults for you):

```bash
./scripts/run-amd-igpu.sh
```

Or run directly:

```bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
./llama.cpp/build/bin/llama-server \
    -m models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf \
    -a qwen3.6-35b \
    -ngl 99 --n-cpu-moe 12 -fa 0 -c 32768 \
    --host 127.0.0.1 --port 8080 \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0
```

---

## Tuning `--n-cpu-moe` — `12` is the sweet spot

`--n-cpu-moe` = how many of the 48 expert layers are forced onto the **CPU** (rest on the
iGPU). There are two regimes — don't conflate them:

**Normal prompts (interactive).** Speed tracks how many experts are on the iGPU:

| `--n-cpu-moe` | experts on iGPU | real-world t/s | verdict |
|---:|---:|---:|---|
| 0 | 48 (all) | ~17 | fastest, but **HANGS on large prompts** — don't use |
| **12** ✅ | 36 | **~12** | **the balance: fast + stable (default)** |
| 99 | 0 | ~7 | bombproof but sluggish |

**Large prompts (≥ ~8K tokens, e.g. opencode over a real codebase).** Everything
bottlenecks on memory bandwidth + thermals and converges to ~9 t/s regardless of the
setting — *and* `0` is the only config that hangs. Stress-tested with an 8.5K-token
prompt: `12 / 24 / 99` all survived; `0` hung every time.

So **`12`** wins: clearly faster than `99` on the prompts you actually type, and unlike
`0` it never hangs.

> ⚠️ **`--n-cpu-moe 0` (full offload) is not usable.** It grabs the 8 GiB shared display
> pool, contends with your desktop, and wedges on any substantial prefill —
> `GPU Hang` → `amdgpu` MODE2 reset → reload → hang. An auto-restart loop just cycles.
> This is GPU-compute overload, not a memory problem.

---

## Context size

- The model's native context is **256K** with heavy GQA, so the KV cache is tiny
  (~80 KB/token). `-c 32768` costs only ~2.5 GiB of KV in GTT.
- You can push `-c` to 65536 / 131072 — it lands in GTT/RAM, not the display pool.
- **Don't quantize the KV cache here.** V-cache quantization needs flash-attn, which we
  keep **off** (`-fa 0`) because RDNA3 iGPU flash-attn kernels are an extra hang source.

---

## Notes & gotchas

- **`Qwen3.6` is a reasoning model.** It emits a long `<think>` block before answering.
  Give it a generous `max_tokens` (200+) or short replies come back empty.
- **`-fa 0`** (flash-attn off) — keep it off on RDNA3 iGPUs for stability.
- **"GPU is in a low-power state" warning** — cosmetic; the GPU wakes on first use. To
  silence it, pin the device awake: `echo on | sudo tee /sys/bus/pci/devices/<pci-id>/power/control`.
- **Other GPU users** (e.g. a stray `ollama serve`) can grab the iGPU concurrently. Stop
  them if you hit contention.

---

## Next steps

- Run it **always-on** as a service → [`../guides/02-run-as-server.md`](../guides/02-run-as-server.md)
- Drive it from **opencode** → [`../guides/03-connect-opencode.md`](../guides/03-connect-opencode.md)
