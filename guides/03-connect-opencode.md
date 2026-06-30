# Connect opencode

[opencode](https://opencode.ai/) is a terminal coding agent. It talks to any
OpenAI-compatible endpoint — which is exactly what `llama-server` exposes at
`http://<host>:8080/v1`. This step is shared across all profiles.

---

## Step 1 — Install opencode

Follow the installer at <https://opencode.ai/>. Then drop the config below into:

- **Linux:** `~/.config/opencode/opencode.jsonc`
- (other OSes: see opencode's docs for the config path)

A ready template is at [`scripts/opencode.jsonc`](../scripts/opencode.jsonc) — copy it and
edit the `baseURL`.

---

## Step 2 — Point it at your server

The only thing you must change is the `baseURL`:

- **Local** (opencode runs on the same machine as the server):

  ```jsonc
  "baseURL": "http://localhost:8080/v1"
  ```

- **Remote** (server is another box on your network — the server must run with
  `--host 0.0.0.0`, see [`02-run-as-server.md`](02-run-as-server.md)):

  ```jsonc
  "baseURL": "http://<server-ip>:8080/v1"   // e.g. http://192.168.1.50:8080/v1
  ```

`apiKey` can be any non-empty string (`"not-needed"`) — llama.cpp doesn't check it.

---

## Step 3 — Run it

```bash
cd /path/to/your/project
opencode
```

Confirm the selected model reads as your local provider (e.g.
`Qwen3.6 35B MoE  local`). If you want a UI for copy/paste, run it inside `tmux` or
`screen` — opencode's built-in select+copy can be finicky.

---

## About the config template

[`scripts/opencode.jsonc`](../scripts/opencode.jsonc) is a generic starting point. Two
parts worth understanding:

### Agent prompts (`build` / `plan`)

A generic developer-assistant preamble — "follow the existing codebase, prefer deleting
over adding, walk the YAGNI decision ladder, never compromise safety to cut code."
**Replace it with your own conventions** (language, style, return codes, whatever your
team uses). It's just a system prompt.

### Permission model

A sensible default for a local agent:

- **Read / glob / grep / list / lsp** → always allowed.
- **Edit, webfetch, websearch** → ask first.
- **Bash** → a whitelist of read-only commands (`ls`, `cat`, `grep`, `df`, `journalctl
  status`, …) is allowed; everything else asks; destructive/VCS commands (`git`, `dd`,
  `mkfs`, `chmod 777`, redirecting to `/…`) are **denied** outright.

Tune to taste, but keep destructive commands gated.

---

## Safety reminders

- It's **a smart autocomplete**, not an oracle. Review every command before it runs.
- Touching something sensitive? Prefer doing it yourself.
- **Never auto-commit** with it.
- It runs on whatever machine you launch it from. The end result is your responsibility —
  it's a tool; using it carelessly is on the user, not the tool.
