# Download the model

Every profile uses the same GGUF model file by default. This step is shared.

**Default model:** `Qwen3.6-35B-A3B` — a ~35B-parameter MoE (only ~3B active per token),
in the `UD-Q4_K_M` quant. ~22 GB on disk.

---

## Get it with the Hugging Face CLI

The `hf` CLI is resumable and verifies hashes — better than a raw `wget` for a 22 GB file.

```bash
# isolated venv so you don't pollute system python
python3 -m venv ~/.venvs/hf && source ~/.venvs/hf/bin/activate
pip install -U "huggingface_hub[cli]"

# download into the repo's models/ directory
hf download unsloth/Qwen3.6-35B-A3B-GGUF Qwen3.6-35B-A3B-UD-Q4_K_M.gguf \
  --local-dir ./models
```

You should end up with `./models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf`.

> The `models/` directory and `*.gguf` files are git-ignored — never commit the weights.

---

## Swapping in a different model

Nothing here is Qwen-specific. To use another GGUF:

1. Download any `*.gguf` (any llama.cpp-supported architecture) into `./models/`.
2. Point the `-m` flag (or the `MODEL` variable in the run scripts) at the new file.
3. Re-tune `--n-cpu-moe` for the new model's size:
   - **Bigger model / less VRAM** → raise `--n-cpu-moe` (more experts on CPU).
   - **Smaller model / more VRAM** → lower it (more on GPU = faster).
   - Non-MoE models ignore `--n-cpu-moe`; use `-ngl` (layers on GPU) instead.
4. Sampling defaults (`--temp`, `--top-p`, etc.) are model-specific — check the model
   card. The values in the run scripts are tuned for Qwen3.6.

---

## Next

Go back to your hardware guide and continue from where it linked you here.
