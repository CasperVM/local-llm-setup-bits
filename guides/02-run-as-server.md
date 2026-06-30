# Run it always-on as a service

By default the run scripts launch the server in your terminal and stop when you close it.
To keep it running across reboots and **auto-restart on crash**, wrap it in a `systemd`
service. This applies to any profile — just point it at the right run script.

> **Bind address matters.** A local-only server uses `--host 127.0.0.1`. To reach it from
> other machines on your network, the run script must use `--host 0.0.0.0` (the NVIDIA
> run script already does; the AMD one is local-only by default — change it if you want
> remote access). Only expose `0.0.0.0` on a trusted network.

---

## Step 1 — Optional: free-resources helper

[`scripts/free-resources.sh`](../scripts/free-resources.sh) kills any stale
`llama-server`, drops the page cache, and prints before/after VRAM+RAM. The service runs
it before each (re)start so a crash-restart starts clean. It's a no-op when nothing is
running, so there's no restart loop.

To let it drop the page cache without a password prompt (optional):

```bash
sudo visudo -f /etc/sudoers.d/drop-caches
# add this line (replace <user> with the account the service runs as):
# <user> ALL=(ALL) NOPASSWD: /usr/bin/tee /proc/sys/vm/drop_caches
```

---

## Step 2 — Install the service unit

A template lives at [`scripts/llama-server.service`](../scripts/llama-server.service).
**Edit the placeholders first** — `<user>` and the paths must match your machine:

```bash
# edit scripts/llama-server.service: set User=, WorkingDirectory=, ExecStart=
sudo cp scripts/llama-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now llama-server
sudo journalctl -u llama-server -f      # watch it come up
```

Key bits of the unit, and why:

- `Restart=on-failure`, `RestartSec=15` — on a crash, wait 15 s and relaunch.
- `StartLimitBurst=3` / `StartLimitIntervalSec=120` — give up after 3 restarts in 2 min
  (don't thrash forever on a persistent fault).
- `LimitMEMLOCK=infinity` — required for `--mlock`. This replaces the manual
  `ulimit -l unlimited` you'd otherwise need, so `--mlock` "just works" under systemd.

---

## Step 3 — Operate it

```bash
sudo systemctl restart llama-server          # restart
sudo systemctl status llama-server           # is it up?
sudo journalctl -u llama-server -f           # live logs

# manual start outside systemd (needs the memlock bump for --mlock):
ulimit -l unlimited && ./scripts/run-nvidia.sh

# clean restart by hand:
./scripts/free-resources.sh --restart run-nvidia.sh
```

Watch GPU memory live (NVIDIA):

```bash
watch -n2 'nvidia-smi --query-gpu=memory.used,memory.free,temperature.gpu,power.draw --format=csv,noheader'
```

---

## Next

Connect a client → [`03-connect-opencode.md`](03-connect-opencode.md)
