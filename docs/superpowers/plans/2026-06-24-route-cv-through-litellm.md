# Route cv through LiteLLM (Project A) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `cv` launch Claude Code routed through onyx's LiteLLM proxy (from both onyx and aqua), with full feature fidelity and Haiku available, so every Claude Code request is logged in LiteLLM's spend DB.

**Architecture:** onyx hosts the LiteLLM proxy (OrbStack docker-compose). `cv` (one chezmoi-managed zsh function on both machines) targets the proxy with a machine-aware base URL — `localhost:4000` on onyx, `onyx.tail5d740c.ts.net:4000` from aqua over Tailscale — guarding that the proxy is up (auto-start locally on onyx, SSH-start on aqua) before launching Claude Code via `ANTHROPIC_BASE_URL`.

**Tech Stack:** zsh (autoload function), LiteLLM (docker-compose on OrbStack), Tailscale, chezmoi (incl. age-encrypted secrets), Claude Code.

## Global Constraints

- onyx Tailscale: IP `100.86.30.80`, MagicDNS FQDN `onyx.tail5d740c.ts.net`, tailnet suffix `tail5d740c.ts.net`.
- Deployed proxy dir (onyx): `~/projects/gamuda/litellm-tracker` (chezmoi source `private_projects/private_gamuda/litellm-tracker/`).
- chezmoi source files: config `…/litellm-tracker/config.yaml`, compose `…/litellm-tracker/docker-compose.yml`, container env `…/litellm-tracker/encrypted_dot_env.age` (→ `~/projects/gamuda/litellm-tracker/.env`).
- Shell secret (`LITELLM_MASTER_KEY`) source: `dot_config/zsh/encrypted_secrets.zsh.tmpl.age` (→ `~/.config/zsh/secrets.zsh`, sourced by `dot_zshenv`).
- cv must route via LiteLLM and **must NOT set** `CLAUDE_CODE_USE_VERTEX`, `ANTHROPIC_VERTEX_PROJECT_ID`, `CLOUD_ML_REGION`.
- cv must keep `CLAUDE_CODE_ENABLE_AUTO_MODE=1`, model defaults `claude-opus-4-8[1m]` / `claude-sonnet-4-6[1m]` / `claude-haiku-4-5@20251001`, and `claude --allow-dangerously-skip-permissions "$@"`.
- Native-Vertex path is replaced (no fallback).
- Commit signing is broken in this environment — every commit uses `git -c commit.gpgsign=false`.
- Edit chezmoi **source** files under `~/.local/share/chezmoi/`, then `chezmoi apply <target>` to deploy. Never edit deployed targets directly.
- Tasks 1–4 run on **onyx** (this machine). Task 5 (aqua) is user-driven/remote.

---

### Task 1: Register cv's Claude model strings in LiteLLM

Add `model_list` aliases so the exact model strings cv sends resolve, with 1M beta on the `[1m]` variants and Haiku available.

**Files:**
- Modify: `private_projects/private_gamuda/litellm-tracker/config.yaml` (append to `model_list`, currently ends after the `claude-sonnet-4-6` entry)

**Interfaces:**
- Produces: proxy model_names `claude-opus-4-8[1m]`, `claude-sonnet-4-6[1m]`, `claude-haiku-4-5@20251001` routable via `/v1/messages`.

- [ ] **Step 1: Add the three aliases to the source config**

Append under `model_list:` in `private_projects/private_gamuda/litellm-tracker/config.yaml`:

```yaml
  - model_name: "claude-opus-4-8[1m]"
    litellm_params:
      model: vertex_ai/claude-opus-4-8
      vertex_project: "os.environ/GCP_PROJECT_ID"
      vertex_location: "global"
      extra_headers: {"anthropic-beta": "context-1m-2025-08-07"}
  - model_name: "claude-sonnet-4-6[1m]"
    litellm_params:
      model: vertex_ai/claude-sonnet-4-6
      vertex_project: "os.environ/GCP_PROJECT_ID"
      vertex_location: "global"
      extra_headers: {"anthropic-beta": "context-1m-2025-08-07"}
  - model_name: "claude-haiku-4-5@20251001"
    litellm_params:
      model: vertex_ai/claude-haiku-4-5
      vertex_project: "os.environ/GCP_PROJECT_ID"
      vertex_location: "global"
```

- [ ] **Step 2: Deploy the config and restart the proxy**

```bash
chezmoi apply ~/projects/gamuda/litellm-tracker/config.yaml
cd ~/projects/gamuda/litellm-tracker && docker compose restart litellm
sleep 5
```
Expected: `chezmoi apply` exits 0; container restarts.

- [ ] **Step 3: Verify the proxy lists the new models**

```bash
curl -s -m 5 http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq -r '.data[].id'
```
Expected: output includes `claude-opus-4-8[1m]`, `claude-sonnet-4-6[1m]`, `claude-haiku-4-5@20251001` (alongside the existing ids).

- [ ] **Step 4: Verify each new model actually routes to Vertex (200 + no error)**

```bash
for m in 'claude-opus-4-8[1m]' 'claude-sonnet-4-6[1m]' 'claude-haiku-4-5@20251001'; do
  printf '%s -> ' "$m"
  curl -s -m 60 http://localhost:4000/v1/messages \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H 'content-type: application/json' -H 'anthropic-version: 2023-06-01' \
    -d "$(jq -n --arg m "$m" '{model:$m,max_tokens:8,messages:[{role:"user",content:"hi"}]}')" \
    | jq -c '{stop:.stop_reason, model:.model, err:(.error.message // null)}'
done
```
Expected: each line shows a `stop` value (e.g. `end_turn`/`max_tokens`) and `err:null`. If any shows an error (e.g. model-not-found or vertex model id wrong), fix the `model:` mapping in the alias before proceeding.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_projects/private_gamuda/litellm-tracker/config.yaml
git -c commit.gpgsign=false commit -m "feat(litellm): register cv claude model aliases (opus/sonnet [1m], haiku)"
```

---

### Task 2: Restrict proxy binding to loopback + Tailscale

Stop exposing `:4000` on all interfaces; serve only loopback (onyx-local) and onyx's Tailscale IP (aqua).

**Files:**
- Modify: `private_projects/private_gamuda/litellm-tracker/docker-compose.yml:7` (the `- "4000:4000"` ports line)

- [ ] **Step 1: Change the ports binding in the source compose**

Replace the line `      - "4000:4000"` under the `litellm` service `ports:` with:

```yaml
      - "127.0.0.1:4000:4000"
      - "100.86.30.80:4000:4000"   # onyx Tailscale IP — reachable within tailnet only
```

- [ ] **Step 2: Deploy and recreate the container (ports change needs recreate, not restart)**

```bash
chezmoi apply ~/projects/gamuda/litellm-tracker/docker-compose.yml
cd ~/projects/gamuda/litellm-tracker && docker compose up -d
sleep 5
```
Expected: container recreated; exits 0.

- [ ] **Step 3: Verify it serves on loopback and Tailscale IP, but NOT on a non-Tailscale address**

```bash
echo "loopback:"; curl -s -m4 http://127.0.0.1:4000/health/liveliness; echo
echo "tailscale:"; curl -s -m4 http://100.86.30.80:4000/health/liveliness; echo
echo "listeners (expect only 127.0.0.1 and 100.86.30.80, no *):"
lsof -nP -iTCP:4000 -sTCP:LISTEN | awk 'NR>1{print $9}'
```
Expected: both curls print `"I'm alive!"`; the listener list shows `127.0.0.1:4000` and `100.86.30.80:4000` and **no** `*:4000`.

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_projects/private_gamuda/litellm-tracker/docker-compose.yml
git -c commit.gpgsign=false commit -m "feat(litellm): bind proxy to loopback + tailscale only (not 0.0.0.0)"
```

---

### Task 3: Rewrite `cv` to route through the proxy

Replace the native-Vertex launcher with a machine-aware, proxy-guarded LiteLLM launcher.

**Files:**
- Modify (replace contents): `dot_config/zsh/functions/cv`

**Interfaces:**
- Consumes: proxy from Tasks 1–2; `$LITELLM_MASTER_KEY` (shell env). Model aliases from Task 1.

- [ ] **Step 1: Replace the entire `cv` function file**

Write `dot_config/zsh/functions/cv` as:

```zsh
# cv - Claude Code routed through the LiteLLM proxy on onyx (unified cost tracking).
#      onyx hosts the proxy (~/projects/gamuda/litellm-tracker, OrbStack compose);
#      aqua reaches it over Tailscale. Native-Vertex path retired.
#      See docs/superpowers/specs/2026-06-24-route-cv-through-litellm-design.md
emulate -L zsh

local litellm_dir="$HOME/projects/gamuda/litellm-tracker"
local base
if [[ "$(hostname -s)" == onyx* ]]; then
  base="http://localhost:4000"
else
  base="http://onyx.tail5d740c.ts.net:4000"
fi
local health="${base}/health/liveliness"

# Proxy guard: ensure the proxy is up; auto-start locally on onyx, SSH-start on aqua.
if ! curl -fsS -m 3 "$health" >/dev/null 2>&1; then
  print -u2 "cv: LiteLLM proxy not reachable at ${base} — attempting to start it…"
  if [[ "$(hostname -s)" == onyx* ]]; then
    ( cd "$litellm_dir" && docker compose up -d ) || { print -u2 "cv: failed to start proxy locally"; return 1; }
  else
    ssh onyx "cd ${litellm_dir} && docker compose up -d" || { print -u2 "cv: failed to start proxy on onyx via ssh"; return 1; }
  fi
  local i
  for i in {1..20}; do
    curl -fsS -m 2 "$health" >/dev/null 2>&1 && break
    sleep 1
  done
  if ! curl -fsS -m 2 "$health" >/dev/null 2>&1; then
    print -u2 "cv: proxy still not healthy at ${base}."
    print -u2 "    Start it on onyx with: (cd ${litellm_dir} && docker compose up -d)"
    return 1
  fi
fi

ANTHROPIC_BASE_URL="$base" \
ANTHROPIC_AUTH_TOKEN="$LITELLM_MASTER_KEY" \
CLAUDE_CODE_ENABLE_AUTO_MODE=1 \
ANTHROPIC_DEFAULT_SONNET_MODEL='claude-sonnet-4-6[1m]' \
ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-4-8[1m]' \
ANTHROPIC_DEFAULT_HAIKU_MODEL='claude-haiku-4-5@20251001' \
claude --allow-dangerously-skip-permissions "$@"
```

- [ ] **Step 2: Syntax-check the function body**

```bash
{ echo 'cv() {'; cat ~/.local/share/chezmoi/dot_config/zsh/functions/cv; echo '}'; } | zsh -n && echo "zsh syntax OK"
```
Expected: `zsh syntax OK`.

- [ ] **Step 3: Verify it sets no native-Vertex vars and the base URL logic is correct**

```bash
grep -E 'CLAUDE_CODE_USE_VERTEX|ANTHROPIC_VERTEX_PROJECT_ID|CLOUD_ML_REGION|tmux set-environment' ~/.local/share/chezmoi/dot_config/zsh/functions/cv && echo "LEAK: found forbidden line" || echo "clean: no native-vertex / tmux lines"
```
Expected: `clean: no native-vertex / tmux lines`.

- [ ] **Step 4: Deploy and reload the function**

```bash
chezmoi apply ~/.config/zsh/functions/cv
unfunction cv 2>/dev/null; autoload -Uz cv
echo "reloaded"
```
Expected: `reloaded` (run in an interactive zsh; if executed via the Bash tool, just confirm `chezmoi apply` exits 0 — the user reloads in their shell).

- [ ] **Step 5: Integration check — cv launches Claude Code through the proxy (onyx)**

```bash
cv -p "reply with exactly: ok" 2>&1 | tail -5
```
Expected: prints `ok` (Claude Code responded through the proxy). Then confirm the request was logged:
```bash
curl -s -m10 http://localhost:4000/spend/logs -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  | jq -c 'sort_by(.startTime)|reverse|.[0]|{model,spend}'
```
Expected: a recent entry with a `claude-*` model and `spend` ≥ 0.

- [ ] **Step 6: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/zsh/functions/cv
git -c commit.gpgsign=false commit -m "feat(zsh): route cv through litellm proxy (machine-aware, guarded)"
```

---

### Task 4: Rotate the leaked `LITELLM_MASTER_KEY`

The key leaked into a session transcript. Rotate it in both age stores (container `.env` and shell secrets), redeploy, restart, verify. **Requires the chezmoi age identity to be available** (`chezmoi edit` will decrypt/re-encrypt). This task is guided-manual.

**Files:**
- Modify: `private_projects/private_gamuda/litellm-tracker/encrypted_dot_env.age` (via `chezmoi edit`)
- Modify: `dot_config/zsh/encrypted_secrets.zsh.tmpl.age` (via `chezmoi edit`)

- [ ] **Step 1: Generate a new key**

```bash
NEWKEY="sk-$(openssl rand -hex 24)"; echo "$NEWKEY"
```
Copy the value; you'll paste it into both files.

- [ ] **Step 2: Update the container env**

```bash
chezmoi edit ~/projects/gamuda/litellm-tracker/.env
```
In the editor, set `LITELLM_MASTER_KEY=<NEWKEY>`. Save and exit (chezmoi re-encrypts the `.age` source).

- [ ] **Step 3: Update the shell secret**

```bash
chezmoi edit ~/.config/zsh/secrets.zsh
```
Set the `LITELLM_MASTER_KEY` export to `<NEWKEY>`. Save and exit.

- [ ] **Step 4: Deploy both, restart the proxy, reload the shell secret**

```bash
chezmoi apply ~/projects/gamuda/litellm-tracker/.env ~/.config/zsh/secrets.zsh
cd ~/projects/gamuda/litellm-tracker && docker compose up -d   # picks up new env
source ~/.config/zsh/secrets.zsh
sleep 5
```
Expected: applies clean; container recreated.

- [ ] **Step 5: Verify the new key works and the old one is rejected**

```bash
echo "new key:"; curl -s -m5 -o /dev/null -w "%{http_code}\n" http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY"
echo "old key (should be 401):"; curl -s -m5 -o /dev/null -w "%{http_code}\n" http://localhost:4000/v1/models -H "Authorization: Bearer sk-utpNEACCTm7jJseYXIWrIQ"
```
Expected: new key → `200`; old key → `401`.

- [ ] **Step 6: Commit**

```bash
cd ~/.local/share/chezmoi
git add private_projects/private_gamuda/litellm-tracker/encrypted_dot_env.age dot_config/zsh/encrypted_secrets.zsh.tmpl.age
git -c commit.gpgsign=false commit -m "chore(secrets): rotate LITELLM_MASTER_KEY"
```

---

### Task 5: Deploy and verify on aqua (user-driven / remote)

aqua needs the new dotfiles + rotated key, and its own verification (its proxy-guard path differs — SSH-start). This runs on aqua, not onyx.

**Files:** none (deploy + verify only).

- [ ] **Step 1: Pull and apply dotfiles on aqua**

On aqua:
```bash
chezmoi update   # pulls latest, applies cv + secrets + (unused-on-aqua) litellm files
exec zsh         # reload functions + secrets
```
Expected: `cv` function updated; `$LITELLM_MASTER_KEY` is the rotated value (`echo "${LITELLM_MASTER_KEY:0:6}…"`).

- [ ] **Step 2: Verify aqua reaches onyx's proxy over Tailscale**

On aqua:
```bash
curl -s -m5 http://onyx.tail5d740c.ts.net:4000/health/liveliness; echo
```
Expected: `"I'm alive!"`. If the FQDN fails, try `http://100.86.30.80:4000/health/liveliness`; if only the IP works, update the `else` branch base URL in `cv` to the IP and re-commit (FQDN-resolution caveat from the spec).

- [ ] **Step 3: Verify cv works end-to-end from aqua**

On aqua:
```bash
cv -p "reply with exactly: ok" 2>&1 | tail -5
```
Expected: prints `ok`. Confirm it logged on onyx (run on onyx or via ssh): a fresh `/spend/logs` entry appears.

- [ ] **Step 4: Verify the SSH-start guard (optional, destructive-ish)**

Only if you want to confirm the down-path: on onyx `cd ~/projects/gamuda/litellm-tracker && docker compose stop litellm`, then on aqua run `cv -p "ok"` — expect it to print the "attempting to start" message, SSH-start onyx, poll healthy, then respond. Restart manually if it doesn't recover.

---

## Verification of the whole change

- onyx: `cv -p "ok"` → `ok`, logged in `/spend/logs`; Haiku/Opus/Sonnet aliases all route (Task 1 §4); proxy bound to loopback+tailscale only (Task 2 §3); new key works, old rejected (Task 4 §5).
- aqua: `cv -p "ok"` → `ok` over Tailscale (Task 5).
- A large-context (>200k tokens) request engages 1M — exercise during normal use; if a real session hits the 200k wall, the `[1m]` alias / `extra_headers` beta needs revisiting.

## Testing note

This is infra/launcher glue against a live proxy and a second machine; it is integration-verified (explicit curl/`cv` checks with expected output per task), not unit-tested. The one piece of pure logic — the machine-aware base-URL `case` — is verified by Task 3 §3 (grep) and exercised on both hosts in Tasks 3/5. A standalone unit test of an autoloaded zsh launcher that shells out to curl/docker/ssh would require stubbing all three and add fragile machinery for little gain; the per-task integration checks are the appropriate verification here.

## Notes for the implementer

- Run Tasks 1–4 on **onyx**. Task 5 is **aqua** (the user runs it, or via `ssh aqua`).
- `cv -p "…"` in Task 3 §5 makes a real (tiny) billable Vertex call through the proxy — expected.
- If `docker compose restart` doesn't pick up `.env`/ports changes, use `docker compose up -d` (recreates the container).
- The old leaked key `sk-utpNEACCTm7jJseYXIWrIQ` appears in Task 4 §5 only to assert it's now rejected.
