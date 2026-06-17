# Zsh env/PATH consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate scattered zsh env vars, PATH edits, and secrets into one PATH-building file (`.zshenv`), one secrets file, and a sectioned `exports.zsh`, with a single uniform PATH idiom.

**Architecture:** `.zshenv` (plaintext, all shells) builds the entire PATH declaratively with `typeset -U path` and sources an encrypted secrets file early. `.zshrc` keeps interactive orchestration plus a 3-line PATH re-assert that undoes `path_helper`'s reshuffle on login shells. `exports.zsh` holds all remaining non-sensitive, non-PATH interactive env, grouped into labeled sections.

**Tech Stack:** zsh, chezmoi (age encryption + Go templates), 1Password (`onepasswordRead` at apply time).

## Global Constraints

- **All zsh source files in this repo are age-encrypted.** Read raw (pre-render) source with `chezmoi decrypt <sourcepath>`; render with `chezmoi cat <target>`. Create encrypted source with `chezmoi encrypt < plain > <encrypted_...age>`.
- Secrets (`LITELLM_MASTER_KEY`, `BITBUCKET_*`) must NEVER land in a plaintext source file. Only in `encrypted_secrets.zsh.tmpl.age`.
- chezmoi source-name conventions: `encrypted_` = age-encrypted, `.tmpl` = Go-templated, `dot_` = leading `.` in target.
- Machine hostnames are `aqua` (home server) and `onyx` (work laptop); detected via `{{ eq .chezmoi.hostname "..." }}`. Work email is `{{ .workEmail }}`.
- PATH priority order (first wins): `$PYENV_ROOT/shims`, `/opt/homebrew/bin`, then the rest.
- `path_helper` (`/etc/zprofile`) runs between `.zshenv` and `.zshrc` on login shells and pushes `/usr/bin` ahead of homebrew — the re-assert in `.zshrc` is mandatory.
- No unit-test framework applies; each task's "test" is a verification command in a **fresh** shell (`zsh -lic '...'` for login-interactive, `zsh -c '...'` for non-interactive) plus `chezmoi cat`/`chezmoi apply -n` dry runs. Never `chezmoi apply --force` without asking the user.
- Work entirely in the chezmoi source dir: `~/.local/share/chezmoi`. Commit after each task.

---

### Task 1: Create the encrypted secrets file

**Files:**
- Create: `dot_config/zsh/encrypted_secrets.zsh.tmpl.age` (via `chezmoi encrypt`)

**Interfaces:**
- Produces: a sourced file exporting `LITELLM_MASTER_KEY`, `BITBUCKET_EMAIL`, `BITBUCKET_API_TOKEN`. Sourced by `.zshenv` (Task 2) via `source "$HOME/.config/zsh/secrets.zsh"`.

- [ ] **Step 1: Capture the current secret values/templates** (for reference; do not paste into plaintext)

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi decrypt encrypted_dot_zshenv.age | grep LITELLM_MASTER_KEY
chezmoi decrypt dot_config/zsh/encrypted_exports.zsh.tmpl.age | sed -n '92,102p'
```
Expected: the literal `LITELLM_MASTER_KEY="sk-..."` line, and the `BITBUCKET_EMAIL`/`BITBUCKET_API_TOKEN` template block with the `aqua`/`onyx` `onepasswordRead` conditional.

- [ ] **Step 2: Write the plaintext template to a temp file**

Write `/tmp/secrets.zsh.tmpl` with this exact content (substitute the real `sk-...` value captured in Step 1 for `LITELLM_MASTER_KEY`):

```zsh
# ~/.config/zsh/secrets.zsh — secrets only.
# Encrypted at rest in chezmoi (encrypted_secrets.zsh.tmpl.age); values pulled
# from 1Password at `chezmoi apply` time. Sourced early from .zshenv so every
# shell (interactive, scripts, Claude Bash tool, cron) sees them.
# To rotate a 1Password-backed value: update the item, run `chezmoi apply`.

# LiteLLM proxy master key — consumed by the pi "litellm" provider extension.
export LITELLM_MASTER_KEY="sk-REPLACE_WITH_CAPTURED_VALUE"

# Bitbucket Cloud API credentials for the bitbucket-pr skill scripts.
export BITBUCKET_EMAIL="{{ .workEmail }}"
{{- if eq .chezmoi.hostname "aqua" }}
export BITBUCKET_API_TOKEN="{{ onepasswordRead "op://Gamuda/Bitbucket.AQUA.API_TOKEN/credential" }}"
{{- else if eq .chezmoi.hostname "onyx" }}
export BITBUCKET_API_TOKEN="{{ onepasswordRead "op://Gamuda/Bitbucket.ONYX.API_TOKEN/credential" }}"
{{- end }}
```

- [ ] **Step 3: Encrypt it into the source tree**

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi encrypt < /tmp/secrets.zsh.tmpl > dot_config/zsh/encrypted_secrets.zsh.tmpl.age
shred -u /tmp/secrets.zsh.tmpl 2>/dev/null || rm -f /tmp/secrets.zsh.tmpl
```
Expected: new `.age` file created.

- [ ] **Step 4: Verify it decrypts and renders correctly**

Run:
```bash
chezmoi decrypt dot_config/zsh/encrypted_secrets.zsh.tmpl.age   # raw template, has {{ }}
chezmoi cat ~/.config/zsh/secrets.zsh                            # rendered, real token
```
Expected: raw shows the template directives; rendered shows the real `LITELLM_MASTER_KEY`, `BITBUCKET_EMAIL` = your work email, and a single `BITBUCKET_API_TOKEN` for this host. No template errors.

- [ ] **Step 5: Commit**

```bash
git add dot_config/zsh/encrypted_secrets.zsh.tmpl.age
git commit -m "feat(zsh): add encrypted secrets.zsh (litellm + bitbucket)"
```

---

### Task 2: Replace `.zshenv` with the plaintext PATH-building file

**Files:**
- Create: `dot_zshenv` (plaintext)
- Delete: `encrypted_dot_zshenv.age`

**Interfaces:**
- Consumes: `secrets.zsh` from Task 1.
- Produces: `PATH` (built once), `PYENV_ROOT`, `BUN_INSTALL`, `GOPATH`, `XDG_CONFIG_HOME`, `SSH_AUTH_SOCK` (local only) — all available to every shell. `.zshrc` (Task 4) relies on `$PYENV_ROOT` for its re-assert.

- [ ] **Step 1: Write the new plaintext source `dot_zshenv`**

Write `~/.local/share/chezmoi/dot_zshenv`:

```zsh
# ~/.zshenv — sourced by ALL zsh invocations (interactive, scripts, Claude
# Code's Bash tool, cron). The single home for PATH + PATH-dependent env.
#
# Order matters: .zshenv → /etc/zprofile (path_helper) → .zshrc. On LOGIN
# shells path_helper reshuffles system dirs ahead of homebrew, so .zshrc
# re-asserts priority afterward. Non-login/non-interactive shells read only
# this file and get the correct order directly.

# --- Secrets (LITELLM_MASTER_KEY, BITBUCKET_*) ---------------------------
source "$HOME/.config/zsh/secrets.zsh"

# --- 1Password SSH agent (git commit signing / ssh auth from any shell) ---
# Only set when NOT inside an incoming SSH session, else we'd stomp the
# forwarded agent socket sshd provides (breaks aqua<->onyx agent forwarding).
if [ -z "$SSH_CONNECTION" ]; then
    export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
fi

# --- PATH-dependency vars -------------------------------------------------
export XDG_CONFIG_HOME="$HOME/.config"
export PYENV_ROOT="$HOME/.pyenv"
export BUN_INSTALL="$HOME/.bun"
export GOPATH="$HOME/go"

# --- PATH (declarative; typeset -U auto-dedupes, keeps first occurrence) ---
typeset -U path
path=(
  $PYENV_ROOT/shims
  $PYENV_ROOT/bin
  /opt/homebrew/bin
  $HOME/.local/bin
  $BUN_INSTALL/bin
  $GOPATH/bin
  /opt/homebrew/opt/openjdk/bin
  /opt/homebrew/opt/postgresql@18/bin
  $path
  /Applications/Obsidian.app/Contents/MacOS
  $HOME/.iximiuz/labctl/bin
)

# --- gcloud PATH (completion lives in plugins.zsh) ------------------------
# Prefer brew install (aqua, onyx); fall back to classic Downloads install.
if [ -f "/opt/homebrew/share/google-cloud-sdk/path.zsh.inc" ]; then
    . "/opt/homebrew/share/google-cloud-sdk/path.zsh.inc"
elif [ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]; then
    . "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"
fi
```

- [ ] **Step 2: Remove the encrypted zshenv source**

Run:
```bash
cd ~/.local/share/chezmoi
git rm encrypted_dot_zshenv.age
```

- [ ] **Step 3: Verify render and dry-run apply**

Run:
```bash
chezmoi cat ~/.zshenv | head -5
chezmoi apply -n -v ~/.zshenv
```
Expected: rendered zshenv prints; dry-run shows it will replace `~/.zshenv`. No errors.

- [ ] **Step 4: Verify non-interactive PATH correctness after apply**

Run:
```bash
chezmoi apply ~/.zshenv ~/.config/zsh/secrets.zsh
zsh -c 'echo $PATH' | tr ':' '\n' | head
zsh -c 'echo $GOPATH; echo $BUN_INSTALL; [ -n "$LITELLM_MASTER_KEY" ] && echo LITELLM_OK'
```
Expected: PATH leads with `~/.pyenv/shims`, `~/.pyenv/bin`, `/opt/homebrew/bin`, then the rest; no duplicates. `GOPATH`/`BUN_INSTALL` set; `LITELLM_OK` prints.

- [ ] **Step 5: Commit**

```bash
git add dot_zshenv
git commit -m "refactor(zsh): zshenv builds full PATH declaratively, plaintext"
```

---

### Task 3: Convert `exports.zsh` to a sectioned plaintext template

**Files:**
- Create: `dot_config/zsh/exports.zsh.tmpl` (plaintext template)
- Delete: `dot_config/zsh/encrypted_exports.zsh.tmpl.age`

**Interfaces:**
- Consumes: `PYENV_ROOT` (from zshenv) for the pyenv init cache.
- Produces: `EDITOR`/`VISUAL`, `SUDO_EDITOR`, `FCEDITOR`, `TERMINAL`, `STARSHIP_CONFIG`, `FZF_DEFAULT_COMMAND`, `GOKU_EDN_CONFIG_FILE`, `GIT_CONFIG_*` (ssh only), and project dirs (`GCP_SCRIPTS`, `WTREE`, `INFRA`, `GTECH_DOCS`, `VAULT_PATH`). No PATH edits, no secrets, no `SSH_AUTH_SOCK`.

- [ ] **Step 1: Write the new plaintext template `dot_config/zsh/exports.zsh.tmpl`**

```zsh
# ~/.config/zsh/exports.zsh — non-sensitive, non-PATH interactive env.
# PATH + PATH-dependent vars live in ~/.zshenv. Secrets live in secrets.zsh.

# === Editor ===
# nvr inside an embedded nvim terminal; plain nvim otherwise.
if [ -n "$NVIM_LISTEN_ADDRESS" ]; then
    export VISUAL="nvr -cc split --remote-wait +'set bufhidden=wipe'"
    export EDITOR="$VISUAL"
else
    export VISUAL="nvim"
    export EDITOR="nvim"
fi
export SUDO_EDITOR="nvim"
export FCEDITOR="nvim"

# === Prompt & UI ===
export STARSHIP_CONFIG="$HOME/.config/zsh/starship.toml"
export TERMINAL="Ghostty"

# === Tools ===
export FZF_DEFAULT_COMMAND='rg --files --hidden -g !.git/'
export GOKU_EDN_CONFIG_FILE="$HOME/.config/karabiner/karabiner.edn"

# === Pyenv (interactive init) ===
# Shims dir is already on PATH via .zshenv; this sets up the `pyenv` shell
# function + completion. Cached to avoid the slow `pyenv init` on every shell;
# 'command pyenv rehash' stripped from cache (it blocks on stale locks) and run
# in the background instead. Regenerate: rm ~/.cache/pyenv-init.zsh
_pyenv_cache="${XDG_CACHE_HOME:-$HOME/.cache}/pyenv-init.zsh"
if [[ ! -f "$_pyenv_cache" ]] || [[ "$(realpath "$(command -v pyenv)")" -nt "$_pyenv_cache" ]]; then
    mkdir -p "${_pyenv_cache:h}"
    pyenv init - zsh | grep -v 'command pyenv rehash' > "$_pyenv_cache"
fi
source "$_pyenv_cache"
unset _pyenv_cache
{ rm -f "$PYENV_ROOT/shims/.pyenv-shim"; command pyenv rehash; } &!

# === Git over SSH ===
# Use ssh-keygen for commit signing over SSH (op-ssh-sign can't reach remote 1Password).
if [[ -n "$SSH_CONNECTION" ]]; then
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="gpg.ssh.program"
    export GIT_CONFIG_VALUE_0="ssh-keygen"
fi

# === Project dirs ===
export GCP_SCRIPTS="$HOME/projects/gamuda/gtech-atlas/scripts/"
export INFRA="$HOME/projects/gamuda/gtech-atlas/"
export GTECH_DOCS="$HOME/projects/gamuda/gtech-docs/apps/docs/platform/"
export WTREE="$HOME/projects/gamuda/worktrees"
{{- if eq .chezmoi.hostname "aqua" }}
export VAULT_PATH="$HOME/Documents/Zaid Personal"
{{- end }}
```

Note: dead commented code (`npm-global`, `NVM`, `ZUNO`, `BROWSER`, the duplicate gcloud-completion comment) is intentionally dropped. PATH lines, `SSH_AUTH_SOCK`, and the Bitbucket block are removed (now in zshenv / secrets.zsh).

- [ ] **Step 2: Remove the encrypted exports source**

Run:
```bash
cd ~/.local/share/chezmoi
git rm dot_config/zsh/encrypted_exports.zsh.tmpl.age
```

- [ ] **Step 3: Verify render — no secrets, no PATH edits leaked**

Run:
```bash
chezmoi cat ~/.config/zsh/exports.zsh | grep -nE 'BITBUCKET|LITELLM|path_prepend|path_append|SSH_AUTH_SOCK|^path=|\.local/bin' || echo "CLEAN"
chezmoi cat ~/.config/zsh/exports.zsh | grep -c VAULT_PATH
```
Expected: first prints `CLEAN`; second prints `1` on aqua, `0` on onyx.

- [ ] **Step 4: Apply and verify interactive env**

Run:
```bash
chezmoi apply ~/.config/zsh/exports.zsh
zsh -ic 'echo $EDITOR; echo $STARSHIP_CONFIG; echo $INFRA; command -v pyenv'
```
Expected: `nvim`, the starship path, the INFRA path, and a `pyenv` function/path — no errors.

- [ ] **Step 5: Commit**

```bash
git add dot_config/zsh/exports.zsh.tmpl
git commit -m "refactor(zsh): exports.zsh sectioned, plaintext, PATH/secrets removed"
```

---

### Task 4: Trim `.zshrc` — drop PATH surgery + helpers, add re-assert

**Files:**
- Modify: `encrypted_dot_zshrc.age` (decrypt → edit → re-encrypt)

**Interfaces:**
- Consumes: `$PYENV_ROOT` (from zshenv) for the re-assert.
- Produces: nothing new; removes the `path_prepend`/`path_append` function definitions and all bottom-of-file PATH surgery.

- [ ] **Step 1: Decrypt the current zshrc to a temp file**

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi decrypt encrypted_dot_zshrc.age > /tmp/zshrc.edit
```

- [ ] **Step 2: Edit `/tmp/zshrc.edit`**

Make exactly these changes:

(a) **Delete** the two helper definitions (around lines 31-33):
```zsh
# Add to PATH only if not already present
path_prepend() { [[ ":$PATH:" != *":$1:"* ]] && export PATH="$1:$PATH"; }
path_append()  { [[ ":$PATH:" != *":$1:"* ]] && export PATH="$PATH:$1"; }
```

(b) **Delete** the entire bottom PATH-surgery block:
```zsh
# bun
export BUN_INSTALL="$HOME/.bun"
path_prepend "$BUN_INSTALL/bin"
# Ensure Homebrew binaries (bash 5.x, etc.) take priority over system paths.
# Can't use path_prepend — /etc/paths.d/homebrew already adds it via
# path_helper, so the guard skips it. Remove and re-prepend to force first.
path=("${(@)path:#/opt/homebrew/bin}")
path=(/opt/homebrew/bin $path)

path=("${(@)path:#$PYENV_ROOT/shims}")
path=($PYENV_ROOT/shims $path)
```
…and the lone `path_append "/Users/zaid/.iximiuz/labctl/bin"` line at the very end.

(c) **Insert** this re-assert in place of the deleted bottom block (after the `theme.zsh` source / `zprof` block, anywhere post-`/etc/zprofile`):
```zsh
# path_helper (/etc/zprofile) reshuffles system dirs to the front on login
# shells; force our priority interpreters back ahead of it. typeset -U (set in
# .zshenv) dedupes, so this just moves existing entries — no subshells.
path=($PYENV_ROOT/shims $PYENV_ROOT/bin /opt/homebrew/bin $path)
```

Leave everything else untouched: profiling guard, `ZSH_DIR`, quickterminal/mobile guards, all `source` lines, `fpath`/`autoload`, the `ssh()` function.

- [ ] **Step 3: Verify no helper callers remain and no raw surgery left**

Run:
```bash
grep -nE 'path_prepend|path_append|\(@\)path' /tmp/zshrc.edit || echo "CLEAN"
grep -n 'PYENV_ROOT/shims /opt/homebrew/bin' /tmp/zshrc.edit
```
Expected: first prints `CLEAN`; second shows the one re-assert line.

- [ ] **Step 4: Re-encrypt into the source tree**

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi encrypt < /tmp/zshrc.edit > encrypted_dot_zshrc.age
shred -u /tmp/zshrc.edit 2>/dev/null || rm -f /tmp/zshrc.edit
chezmoi cat ~/.zshrc | tail -20
```
Expected: rendered zshrc ends with the re-assert line and the `ssh()` function; no PATH surgery.

- [ ] **Step 5: Commit**

```bash
git add encrypted_dot_zshrc.age
git commit -m "refactor(zsh): zshrc drops PATH helpers/surgery, adds post-path_helper re-assert"
```

---

### Task 5: Full apply + end-to-end verification + sync

**Files:** none (verification + chezmoi-sync)

- [ ] **Step 1: Dry-run the full apply**

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi apply -n -v
```
Expected: only `~/.zshenv`, `~/.zshrc`, `~/.config/zsh/exports.zsh`, `~/.config/zsh/secrets.zsh` change. Review the diff; nothing unexpected.

- [ ] **Step 2: Apply**

Run: `chezmoi apply`
Expected: clean, no errors.

- [ ] **Step 3: Login-interactive shell — PATH order correct after path_helper**

Run:
```bash
zsh -lic 'print -l $path' | head -6
zsh -lic 'echo $PATH' | tr ':' '\n' | sort | uniq -d
```
Expected: first lists `~/.pyenv/shims`, `~/.pyenv/bin`, `/opt/homebrew/bin` ahead of `/usr/bin`; second (duplicate check) prints nothing.

- [ ] **Step 4: Resolve key tools + secrets in a fresh shell**

Run:
```bash
zsh -lic 'command -v python pyenv brew psql java bun; echo $LITELLM_MASTER_KEY $BITBUCKET_API_TOKEN >/dev/null && echo SECRETS_OK'
```
Expected: each tool resolves to its expected (homebrew/pyenv) path; `SECRETS_OK` prints.

- [ ] **Step 5: Non-interactive (Claude Bash tool parity) check**

Run:
```bash
zsh -c 'command -v python brew; echo $PATH' | tr ':' '\n' | head -4
```
Expected: pyenv shims + homebrew present and ahead of system dirs even without zshrc.

- [ ] **Step 6: Startup not regressed**

Run: `,zsh-bench` (if available) or `for i in 1 2 3; do time zsh -lic exit; done`
Expected: comparable to before (no new per-entry subshell guards; should be equal or faster).

- [ ] **Step 7: Sync via chezmoi-sync skill**

Invoke the `chezmoi-sync` skill to validate, commit any remainder, and push.

---

## Self-Review

**Spec coverage:** layering table → Tasks 2/3/4; PATH block → Task 2; re-assert → Task 4; secrets file → Task 1; exports sectioning + pruning → Task 3; GOPATH export → Task 2; verification list → Task 5. All covered.

**Placeholder scan:** the only intentional placeholder is `sk-REPLACE_WITH_CAPTURED_VALUE` in Task 1 Step 2, captured live in Step 1 — not a plan gap.

**Type/name consistency:** `secrets.zsh` target name consistent across Tasks 1–2; `$PYENV_ROOT`/`$BUN_INSTALL`/`$GOPATH` defined in Task 2, consumed in Tasks 3–4; re-assert line string identical in Task 4 Step 2(c) and its grep in Step 3.
