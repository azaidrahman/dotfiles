# LiteLLM Proxy Guard Refactor + omp Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the duplicated LiteLLM proxy guard into a single `_litellm_proxy` autoloaded function that lazily fetches `LITELLM_MASTER_KEY` from 1Password and exports all downstream env vars, then slim `cv`/`piv` to call it and add a new `omv` wrapper for omp.

**Architecture:** `_litellm_proxy` is the single source of truth for: host-aware URL resolution, lazy 1Password key fetch, health-check/auto-start guard, and the three env vars every LiteLLM agent needs (`LITELLM_MASTER_KEY`, `LITELLM_API_KEY`, `LITELLM_BASE_URL`). Each wrapper (`cv`, `piv`, `omv`) is a thin shell: call the guard, set the TMUX marker, exec the agent, unset. `~/.omp/agent/models.yml` is plain YAML — no host-aware template needed because omp reads `LITELLM_BASE_URL` from env.

**Tech Stack:** zsh autoloaded functions, chezmoi (age encryption), `op` CLI (1Password), docker compose (onyx only), omp v16+.

## Global Constraints

- All function files live under `dot_config/zsh/functions/` — no subfolders, no `.zsh` extension (autoload convention).
- `_litellm_proxy` must work in non-interactive shells (no `zle`, no prompts). Use `print -u2` for errors.
- `LITELLM_MASTER_KEY` must never be written to stdout or a non-encrypted file.
- omp models.yml lives at `dot_omp/agent/models.yml` — plain YAML, no chezmoi template. Base URL comes from the `LITELLM_BASE_URL` env var exported by `_litellm_proxy`.
- Tailscale MagicDNS name for onyx: `onyx` (short, as in `http://onyx:4000`). Onyx detects via `${HOST%%.*} == "onyx"`.
- 1Password reference: `op://Personal Development/LiteLLM login/API Key`

---

### Task 1: Create `_litellm_proxy` shared guard

**Files:**
- Create: `dot_config/zsh/functions/_litellm_proxy`

**Interfaces:**
- Produces:
  - `REPLY` — base URL without trailing slash or `/v1` (e.g. `http://localhost:4000`)
  - `LITELLM_MASTER_KEY` — exported; used by `cv` as `ANTHROPIC_AUTH_TOKEN`
  - `LITELLM_API_KEY` — exported alias of `LITELLM_MASTER_KEY`; read natively by omp and pi
  - `LITELLM_BASE_URL` — exported as `${base}/v1`; read natively by omp as provider base URL
- Returns non-zero on any failure; callers do `_litellm_proxy || return $?`
- Consumed by: `cv`, `piv`, `omv` (Tasks 2–4)

- [ ] **Step 1: Create the function file**

```zsh
# dot_config/zsh/functions/_litellm_proxy
# _litellm_proxy — shared guard for all LiteLLM-backed agent wrappers.
#
# Exports: LITELLM_MASTER_KEY, LITELLM_API_KEY, LITELLM_BASE_URL
# Sets:    REPLY to the base URL (no trailing slash, no /v1)
# Lazy:    fetches key from 1Password only on first call per session.
# Guard:   health-checks proxy; auto-starts docker compose on onyx if down.
# Returns: non-zero on any failure.
emulate -L zsh

local litellm_dir="$HOME/projects/gamuda/litellm-tracker"
local base

if [[ "${HOST%%.*}" == "onyx" ]]; then
  base="http://localhost:4000"
else
  base="http://onyx:4000"
fi

# Lazy key fetch — only hits 1Password once per shell session.
if [[ -z "$LITELLM_MASTER_KEY" ]]; then
  print -u2 "_litellm_proxy: fetching LITELLM_MASTER_KEY from 1Password…"
  LITELLM_MASTER_KEY="$(op read 'op://Personal Development/LiteLLM login/API Key')" || {
    print -u2 "_litellm_proxy: op read failed — is 1Password unlocked?"
    return 1
  }
  export LITELLM_MASTER_KEY
  export LITELLM_API_KEY="$LITELLM_MASTER_KEY"   # native var for omp/pi
  export LITELLM_BASE_URL="${base}/v1"            # native var for omp/pi base URL
fi

# Health check + conditional auto-start.
local health="${base}/health/liveliness"
if ! curl -fsS -m 3 "$health" >/dev/null 2>&1; then
  print -u2 "_litellm_proxy: proxy not reachable at ${base} — attempting to start…"
  if [[ "${HOST%%.*}" == "onyx" ]]; then
    if [[ ! -f "$litellm_dir/docker-compose.yml" ]]; then
      print -u2 "_litellm_proxy: compose file missing at $litellm_dir — run 'chezmoi apply'."
      return 1
    fi
    if ! docker info >/dev/null 2>&1; then
      print -u2 "_litellm_proxy: Docker isn't running — start Docker then retry."
      return 1
    fi
    docker compose -f "$litellm_dir/docker-compose.yml" up -d >/dev/null 2>&1 || {
      print -u2 "_litellm_proxy: docker compose up -d failed."
      return 1
    }
    local i
    for i in {1..20}; do
      curl -fsS -m 2 "$health" >/dev/null 2>&1 && break
      sleep 1
    done
    if ! curl -fsS -m 2 "$health" >/dev/null 2>&1; then
      print -u2 "_litellm_proxy: proxy still not healthy after 20s."
      return 1
    fi
    print -u2 "_litellm_proxy: proxy is up."
  else
    print -u2 "_litellm_proxy: proxy not reachable at ${base}."
    print -u2 "               Start it on onyx: ssh onyx 'cd ${litellm_dir} && docker compose up -d'"
    return 1
  fi
fi

REPLY="$base"
```

- [ ] **Step 2: Verify autoload and all three exports**

```zsh
autoload -Uz _litellm_proxy
_litellm_proxy && echo "REPLY=$REPLY" && echo "BASE_URL=$LITELLM_BASE_URL"
```

Expected (stderr): `_litellm_proxy: fetching LITELLM_MASTER_KEY from 1Password…`
Expected (stdout): `REPLY=http://localhost:4000` (onyx) or `REPLY=http://onyx:4000` (aqua), plus `BASE_URL=<base>/v1`

- [ ] **Step 3: Commit**

```bash
git add dot_config/zsh/functions/_litellm_proxy
git commit -m "feat(zsh): add _litellm_proxy — shared guard with lazy 1Password key fetch"
```

---

### Task 2: Slim down `cv`

**Files:**
- Modify: `dot_config/zsh/functions/cv`

**Interfaces:**
- Consumes: `_litellm_proxy` → `REPLY` (for `ANTHROPIC_BASE_URL`), `LITELLM_MASTER_KEY`

- [ ] **Step 1: Replace `cv` with the slimmed version**

```zsh
# dot_config/zsh/functions/cv
# cv - Claude Code routed through the LiteLLM proxy on onyx (Vertex backend).
#      See docs/superpowers/specs/2026-06-24-route-cv-through-litellm-design.md
#      Key fetched lazily from 1Password by _litellm_proxy on first call per session.
emulate -L zsh

_litellm_proxy || return $?

[[ -n "$TMUX" ]] && tmux set -p @claude_provider litellm 2>/dev/null

ANTHROPIC_BASE_URL="$REPLY" \
ANTHROPIC_AUTH_TOKEN="$LITELLM_MASTER_KEY" \
CLAUDE_CODE_ENABLE_AUTO_MODE=1 \
ANTHROPIC_DEFAULT_SONNET_MODEL='claude-sonnet-4-6[1m]' \
ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-4-8[1m]' \
ANTHROPIC_DEFAULT_HAIKU_MODEL='claude-haiku-4-5@20251001' \
claude --allow-dangerously-skip-permissions "$@"
local rc=$?

[[ -n "$TMUX" ]] && tmux set -pu @claude_provider 2>/dev/null
return $rc
```

- [ ] **Step 2: Smoke-test in a fresh shell**

Confirm `LITELLM_MASTER_KEY` is unset first:
```zsh
echo "key=${LITELLM_MASTER_KEY:-<not set>}"
cv --version
```
Expected: 1Password fetch message (stderr), then Claude version. Second run in same shell: no fetch.

- [ ] **Step 3: Commit**

```bash
git add dot_config/zsh/functions/cv
git commit -m "refactor(zsh): slim cv — delegate proxy guard to _litellm_proxy"
```

---

### Task 3: Slim down `piv`

**Files:**
- Modify: `dot_config/zsh/functions/piv`

**Interfaces:**
- Consumes: `_litellm_proxy` → `LITELLM_API_KEY`, `LITELLM_BASE_URL` (read natively by pi)

- [ ] **Step 1: Replace `piv` with the slimmed version**

```zsh
# dot_config/zsh/functions/piv
# piv - Pi coding agent on the Vertex backend (Gemini/Claude via LiteLLM).
#       Key and base URL exported by _litellm_proxy; pi reads them natively.
#
#   piv [pi-args...]                              Default: gemini-3.5-flash
#   piv --model claude-opus-4-8
#   PI_LITELLM_MODEL=gemini-3.1-pro-preview piv   Override model for this invocation.
#
#   `piv` owns the @claude_provider TMUX marker — keep it here, not in `pi`.
emulate -L zsh

_litellm_proxy || return $?

local _piv_model="${PI_LITELLM_MODEL:-gemini-3.5-flash}"

[[ -n "$TMUX" ]] && tmux set -p @claude_provider litellm 2>/dev/null

command pi --provider litellm --model "$_piv_model" "$@"
local rc=$?

[[ -n "$TMUX" ]] && tmux set -pu @claude_provider 2>/dev/null
return $rc
```

- [ ] **Step 2: Smoke-test**

```zsh
piv --version
PI_LITELLM_MODEL=gemini-3.1-pro-preview piv --print "hello"
```
Expected: key fetch on first call, pi version, then a response from Pro.

- [ ] **Step 3: Commit**

```bash
git add dot_config/zsh/functions/piv
git commit -m "refactor(zsh): slim piv — delegate proxy guard to _litellm_proxy"
```

---

### Task 4: Create `omv` and `omvres`

`omv` is structurally identical to `piv` — only the command and model env var differ.

**Files:**
- Create: `dot_config/zsh/functions/omv`
- Create: `dot_config/zsh/functions/omvres`

**Interfaces:**
- Consumes: `_litellm_proxy` → `LITELLM_API_KEY`, `LITELLM_BASE_URL` (read natively by omp)
- `OMP_LITELLM_MODEL` env var overrides default model (mirrors `PI_LITELLM_MODEL` pattern)

- [ ] **Step 1: Create `omv`**

```zsh
# dot_config/zsh/functions/omv
# omv - omp coding agent via LiteLLM proxy (Vertex backend).
#       Mirrors `piv` for omp. Key and base URL exported by _litellm_proxy.
#
#   omv [omp-args...]                             Default: gemini-3.1-pro-preview
#   omv --model claude-opus-4-8
#   OMP_LITELLM_MODEL=gemini-3.5-flash omv        Override model for this invocation.
emulate -L zsh

_litellm_proxy || return $?

local _omv_model="${OMP_LITELLM_MODEL:-gemini-3.1-pro-preview}"

[[ -n "$TMUX" ]] && tmux set -p @claude_provider litellm 2>/dev/null

command omp --provider litellm --model "$_omv_model" "$@"
local rc=$?

[[ -n "$TMUX" ]] && tmux set -pu @claude_provider 2>/dev/null
return $rc
```

- [ ] **Step 2: Create `omvres`**

```zsh
# dot_config/zsh/functions/omvres
# omvres - resume the most recent omv session.
omv --resume "$@"
```

- [ ] **Step 3: Smoke-test**

```zsh
omv --version
OMP_LITELLM_MODEL=gemini-3.5-flash omv --print "say hi"
```
Expected: key fetch (if not cached), omp version, then Gemini Flash response via LiteLLM.

- [ ] **Step 4: Commit**

```bash
git add dot_config/zsh/functions/omv dot_config/zsh/functions/omvres
git commit -m "feat(zsh): add omv/omvres — omp routed through LiteLLM proxy"
```

---

### Task 5: Add omp models.yml

Gives omp full model discovery and sensible role defaults. No chezmoi template needed — base URL comes from `LITELLM_BASE_URL` env var (exported by `_litellm_proxy`), so this is plain YAML on all machines.

**Files:**
- Create: `dot_omp/agent/models.yml`

- [ ] **Step 1: Create the file**

```yaml
# dot_omp/agent/models.yml
# omp model config — chezmoi-managed. Base URL injected via LITELLM_BASE_URL env
# var (set by _litellm_proxy at launch). API key via LITELLM_API_KEY (same source).
providers:
  litellm:
    api: openai-completions
    discovery:
      type: litellm

modelRoles:
  default: litellm/claude-sonnet-4-6
  smol:    litellm/gemini-3.5-flash
  slow:    litellm/claude-opus-4-8
  plan:    litellm/claude-opus-4-8
```

- [ ] **Step 2: Apply and verify**

```zsh
chezmoi apply ~/.omp/agent/models.yml
cat ~/.omp/agent/models.yml
```
Expected: plain YAML, no template markers.

- [ ] **Step 3: Verify omp discovers models**

```zsh
omv --print "list the models you can access"
```
Expected: mentions `claude-sonnet-4-6`, `gemini-3.5-flash`, etc.

- [ ] **Step 4: Commit**

```bash
git add dot_omp/agent/models.yml
git commit -m "feat(omp): add chezmoi-managed models.yml with LiteLLM discovery"
```

---

### Task 6: Remove `LITELLM_MASTER_KEY` from secrets.zsh

The key is now fetched lazily by `_litellm_proxy`. Keeping it in `secrets.zsh` is redundant and runs an age decrypt on every shell spawn for no benefit.

**Note:** This file is age-encrypted — edit via `chezmoi edit`, not directly.

- [ ] **Step 1: Edit the secrets template**

```zsh
chezmoi edit ~/.config/zsh/secrets.zsh
```

Remove the `export LITELLM_MASTER_KEY=...` line. Save — chezmoi re-encrypts automatically.

- [ ] **Step 2: Apply and verify key absent in a new shell**

Open a fresh terminal:
```zsh
echo "key=${LITELLM_MASTER_KEY:-<not set>}"
```
Expected: `key=<not set>`

- [ ] **Step 3: Verify cv still works end-to-end**

```zsh
cv --version
```
Expected: 1Password fetch message, then Claude version.

- [ ] **Step 4: Commit**

```bash
git add dot_config/zsh/encrypted_secrets.zsh.tmpl.age
git commit -m "chore(secrets): remove LITELLM_MASTER_KEY — fetched lazily from 1Password"
```

---

### Task 7: Chezmoi sync + cross-machine check

- [ ] **Step 1: Apply everything locally**

```zsh
chezmoi apply
```
Verify no errors. Check `~/.omp/agent/models.yml` exists.

- [ ] **Step 2: Push**

```zsh
cd ~/.local/share/chezmoi && git push
```

- [ ] **Step 3: On onyx — pull and verify**

```zsh
chezmoi update
echo "key=${LITELLM_MASTER_KEY:-<not set>}"   # should be <not set>
cv --version                                   # triggers op read on first use
```

- [ ] **Step 4: Verify TMUX marker lifecycle**

Inside a tmux session, run `omv --print "hello"` and while it runs in another pane:
```zsh
tmux show -p @claude_provider
```
Expected: `litellm`. After `omv` exits: value should be unset.
