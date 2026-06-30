# Larger NVIDIA GPU (~15 GB+, CUDA)

Running the MoE model on a server-class NVIDIA card with ~15 GB+ of VRAM via llama.cpp's
CUDA backend. This is the "always-on inference box" profile.

> **Reference machine:** NVIDIA A2 (15 GB VRAM) + 45 GB RAM, Ubuntu 24.04. Verified
> working as an always-on server. Any modern data-center or workstation card with similar
> VRAM works the same way.

---

## Step 1 — The CUDA gotcha (read this first)

On Ubuntu 24.04, `sudo apt install nvidia-cuda-toolkit` gives you **CUDA 12.0 (Jan 2023)**,
which is too old for current llama.cpp and crashes with `device kernel image is invalid`.

The **driver** and the **toolkit** are versioned independently — a recent driver supports
a much newer CUDA than apt ships. Check your driver's CUDA ceiling with `nvidia-smi` (top
right), then install a matching toolkit from NVIDIA's own repo:

```bash
# drop the stale apt version
sudo apt remove --purge nvidia-cuda-toolkit && sudo apt autoremove

# add NVIDIA's repo (Ubuntu 24.04 keyring shown; pick the one for your distro)
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update

# install a toolkit at/under your driver's CUDA ceiling (e.g. 13.2)
sudo apt install -y cuda-toolkit-13-2
export PATH=/usr/local/cuda/bin:$PATH
nvcc --version    # confirm the version
```

- No reboot needed — that's only for replacing the *driver*, not the toolkit.
- If `cuda-toolkit-13-2` isn't listed:
  `apt-cache search cuda-toolkit | grep -E "cuda-toolkit-1[23]"` and take the highest at
  or below your driver ceiling.
- To make `nvcc` persist for future rebuilds, add the `export PATH` to `~/.bashrc` (or
  `/etc/profile.d/cuda.sh`). Use the `/usr/local/cuda` symlink, not the versioned path, so
  it survives a toolkit bump. Only the **build** needs `nvcc`; the running server doesn't.

---

## Step 2 — Build llama.cpp

```bash
# pinned to the release these configs were built & tested against.
# tag b9843 == commit 86b94708f22478f900b76ca02e316f4f3418faff
git clone --depth 1 --branch b9843 https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
rm -rf build
cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
./build/bin/llama-server --version    # smoke test
```

> Shortcut: if you have another machine with the same GPU generation already built, you
> can `rsync` its `build/` dir over instead of rebuilding:
> `rsync -avP /path/to/llama.cpp/build/ user@host:~/local-llm-setup-bits/llama.cpp/build/`

---

## Step 3 — Download the model

→ **[`../guides/01-download-model.md`](../guides/01-download-model.md)**. Come back when done.

---

## Step 4 — Run it

Use the helper script (it frees stale resources first, then launches):

```bash
ulimit -l unlimited      # needed for --mlock on a manual run; the systemd unit handles this
./scripts/run-nvidia.sh
```

Or run directly:

```bash
./llama.cpp/build/bin/llama-server \
    -m models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf \
    -a qwen3.6-35b \
    -ngl 99 --n-cpu-moe 20 -np 2 -c 49152 \
    --no-mmap --mlock \
    --cache-type-k q4_0 --cache-type-v q4_0 \
    --flash-attn auto \
    --presence-penalty 1.5 \
    --host 0.0.0.0 --port 8080 \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0
```

What the non-obvious flags do:

- `--n-cpu-moe 20` — 20 expert layers on CPU. Good balance for ~15 GB VRAM. **More VRAM →
  lower this** (more on GPU = faster); less VRAM → raise it.
- `-np 2` — 2 parallel request slots (handy for a shared server).
- `--mlock` + `--no-mmap` — lock weights in RAM, don't memory-map; avoids page-fault
  stalls on a long-running server. Needs `RLIMIT_MEMLOCK=unlimited`.
- `--cache-type-k/v q4_0` — quantized KV cache to save VRAM (CUDA flash-attn supports it).
- `--flash-attn auto` — let llama.cpp enable FA where supported (fine on NVIDIA).

---

## Step 5 — Make it always-on + connect a client

- Run as a `systemd` service (auto-restart, memlock handled) →
  [`../guides/02-run-as-server.md`](../guides/02-run-as-server.md)
- Drive it from opencode (local or over the network) →
  [`../guides/03-connect-opencode.md`](../guides/03-connect-opencode.md)

---

## Quick reference

```bash
# clean restart by hand
./scripts/free-resources.sh --restart run-nvidia.sh

# service
sudo systemctl restart llama-server
sudo journalctl -u llama-server -f

# live VRAM watch
watch -n2 'nvidia-smi --query-gpu=memory.used,memory.free,temperature.gpu,power.draw --format=csv,noheader'
```

> **`Qwen3.6` is a reasoning model** — it emits a long `<think>` block first. Give clients
> a generous `max_tokens` (200+) or short answers come back empty.
