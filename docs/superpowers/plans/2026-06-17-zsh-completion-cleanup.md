# Zsh Completion Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate all shell-completion config into one documented `completions.zsh` module, fix the init bugs (double `bashcompinit`, docker's full `compinit`, per-startup `labctl`/`jj`), and add the missing `zinit cdreplay`.

**Architecture:** Completion responsibilities split three ways — the `compinit` engine stays in `launch.zsh`; plugin completions + `zinit cdreplay -q` live in `plugins.zsh`; tool completions (lazy), custom compdefs, and styling move into a new `completions.zsh`. `.zshrc`'s completion junk drawer is deleted and replaced by one `source` line.

**Tech Stack:** zsh, zinit (plugin manager), chezmoi (dotfile manager, with age encryption for `.zshrc`).

## Global Constraints

- **chezmoi-managed repo.** Edits must land in chezmoi *source*, not just the deployed copy.
  - Plain files (`dot_config/zsh/*.zsh`): edit the source in `~/.local/share/chezmoi/`, then `chezmoi apply` to deploy.
  - Encrypted `~/.zshrc` (source = `encrypted_dot_zshrc.age`): edit the live `~/.zshrc`, then `chezmoi re-add ~/.zshrc` to re-encrypt into source. age re-encryption always produces a diff (random nonce) — expected, not a change in content.
- **No completion test framework exists.** Verification is: `zsh -n <file>` (syntax), a clean interactive start `zsh -ic exit` (no errors printed), the `,zsh-bench` startup benchmark, and manual `<cmd> <TAB>` checks. These replace automated tests for this plan.
- **Never break the interactive shell between commits.** Each task must leave `zsh -ic exit` clean.
- Source-file paths are exact: `~/.local/share/chezmoi/dot_config/zsh/`.

---

## File Structure

- **Create:** `dot_config/zsh/completions.zsh` — single home for tool completions (lazy), custom compdefs, completion styling, and the lazy/bashcompinit helpers.
- **Modify:** `dot_config/zsh/plugins.zsh` — add `zinit cdreplay -q` at end.
- **Modify:** `dot_config/zsh/general.zsh` — remove the 4 completion `zstyle` lines (moved to `completions.zsh`).
- **Modify:** `~/.zshrc` (encrypted source) — delete the completion junk drawer; add one `source "$ZSH_DIR/completions.zsh"` line.

Unchanged: `launch.zsh` (compinit engine), the kubectl/gcloud completions already in `plugins.zsh`, and `.zshrc`'s PATH / `BUN_INSTALL` / homebrew-pyenv reorder / `ssh()` blocks.

---

### Task 1: Create `completions.zsh` (inert — not yet sourced)

Creating the module first, before wiring it in, means this commit changes no runtime behavior (the file exists but nothing sources it). Safe to land and verify in isolation.

**Files:**
- Create: `~/.local/share/chezmoi/dot_config/zsh/completions.zsh`

**Interfaces:**
- Produces: shell functions `_lazy_completion <cmd> <load-code>` and `_ensure_bashcompinit`; lazy wrappers for `jj`, `labctl`, `docker`, `terraform`, `terramate`; compdefs `_git-ship`, `_gwtcd`. Consumed by `.zshrc` in Task 3 (which only sources the file).

- [ ] **Step 1: Capture the startup-time baseline (before any change)**

Run in an interactive shell:
```bash
,zsh-bench 10
```
Record the printed `Average:` line — this is the pre-cleanup baseline to compare against in Task 3.

- [ ] **Step 2: Create the source file with full content**

Create `~/.local/share/chezmoi/dot_config/zsh/completions.zsh` with exactly:

```zsh
# ~/.config/zsh/completions.zsh
#
# Single home for shell completion config that *we* own.
#
# Where completion lives (the whole picture):
#   launch.zsh        the engine — autoload + cached `compinit` (24h rebuild,
#                     `-C` fast path). Do NOT duplicate compinit here.
#   plugins.zsh       plugin-provided completions (zsh-completions, fzf-tab)
#                     plus `zinit cdreplay -q`, which replays the compdefs that
#                     those turbo-deferred plugins register after compinit.
#   completions.zsh   (this file) completion *styling* (zstyle), our own custom
#                     compdefs, and lazily-loaded per-tool completions.
#
# Lazy-load pattern:
#   `_lazy_completion <cmd> '<code>'` defines a thin wrapper for <cmd>. The first
#   time you RUN <cmd>, the wrapper removes itself, runs <code> to load the real
#   completion, then execs <cmd>. Tradeoff: `<cmd> <TAB>` does nothing until
#   you've invoked <cmd> once this session. Worth it — these loaders are slow
#   (they shell out to the tool) and most shells never touch most of them.
#
# Add a new tool completion:
#   zsh-native (tool prints a compdef/_tool script):
#       _lazy_completion mytool 'source <(mytool completion zsh)'
#   bash-style (tool uses `complete -C`): call _ensure_bashcompinit first:
#       _lazy_completion mytool '_ensure_bashcompinit; complete -C /path mytool'

# --- helpers ---------------------------------------------------------------

# Lazy-load a command's completion on first invocation.
#   $1 = command name, $2 = code that loads its completion.
_lazy_completion() { eval "$1() { unfunction $1; $2; $1 \"\$@\"; }"; }

# Run bashcompinit at most once (needed by `complete -C` style completions).
_ensure_bashcompinit() {
    (( ${+_lazy_bashcompinit} )) && return
    autoload -U +X bashcompinit && bashcompinit
    _lazy_bashcompinit=1
}

# --- styles ----------------------------------------------------------------

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors '${(s.:.)LS_COLORS}'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

# --- custom compdefs (cheap, eager) ----------------------------------------

# `git ship` alias (defined in ~/.gitconfig); git auto-discovers _git-<sub>.
_git-ship() { _arguments '1: :__git_branch_names'; }

# gwtcd: complete on git worktree basenames.
_gwtcd() {
    local -a names
    names=(${(f)"$(git worktree list 2>/dev/null | awk '{print $1}' | xargs -n1 basename)"})
    _describe 'worktree' names
}
compdef _gwtcd gwtcd

# bun: static completion file, cheap to source eagerly.
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# --- lazy tool completions -------------------------------------------------

_lazy_completion jj        'source <(jj util completion zsh)'
_lazy_completion labctl    'source <(labctl completion zsh)'
_lazy_completion docker    'fpath=("$HOME/.docker/completions" $fpath); autoload -Uz _docker && compdef _docker docker'
_lazy_completion terraform '_ensure_bashcompinit; complete -o nospace -C /opt/homebrew/bin/terraform terraform'
_lazy_completion terramate '_ensure_bashcompinit; complete -o nospace -C /opt/homebrew/bin/terramate terramate'
```

- [ ] **Step 3: Syntax-check the new file**

Run:
```bash
zsh -n ~/.local/share/chezmoi/dot_config/zsh/completions.zsh && echo OK
```
Expected: `OK` (no parse errors).

- [ ] **Step 4: Deploy and confirm it loads cleanly when sourced manually**

Run:
```bash
chezmoi apply ~/.config/zsh/completions.zsh
zsh -ic 'source ~/.config/zsh/completions.zsh && echo LOADED' 2>&1
```
Expected: `LOADED` with no errors above it. (Sourcing it standalone in an interactive shell is safe because `compinit` already ran for that shell, so `compdef` works.)

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/zsh/completions.zsh
git commit -m "feat(zsh): add completions.zsh module (not yet wired in)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Add `zinit cdreplay -q` to `plugins.zsh`

Independent, low-risk one-liner. Landing it before the `.zshrc`/`general.zsh` cutover keeps the diffs reviewable and the shell working at every step.

**Files:**
- Modify: `~/.local/share/chezmoi/dot_config/zsh/plugins.zsh`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing other tasks reference.

- [ ] **Step 1: Add the cdreplay call after the kubectl block**

In `~/.local/share/chezmoi/dot_config/zsh/plugins.zsh`, immediately after the closing `fi` of the kubectl-completion `if` block (and before the commented-out zoxide gh-r snippet), insert:

```zsh

# Replay compdefs captured from turbo-deferred plugins (zsh-completions,
# fzf-tab). They call `compdef` AFTER the early compinit in launch.zsh, so
# zinit queues those calls; cdreplay applies them in one pass.
zinit cdreplay -q
```

- [ ] **Step 2: Syntax-check**

Run:
```bash
zsh -n ~/.local/share/chezmoi/dot_config/zsh/plugins.zsh && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Deploy and confirm a clean interactive start**

Run:
```bash
chezmoi apply ~/.config/zsh/plugins.zsh
zsh -ic exit 2>&1; echo "exit=$?"
```
Expected: no error output, `exit=0`. (If `cdreplay` printed a warning about no compdefs to replay, that is benign, but there should be none with the turbo plugins present.)

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/zsh/plugins.zsh
git commit -m "fix(zsh): replay turbo-deferred plugin compdefs via zinit cdreplay

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Cut over — wire in `completions.zsh`, strip `.zshrc` and `general.zsh`

This task is atomic: it sources `completions.zsh` from `.zshrc` AND removes the now-duplicate logic from `.zshrc` and `general.zsh` in one commit. Doing them together avoids any intermediate state where the styling/compdefs exist in neither place or in both.

**Files:**
- Modify: `~/.zshrc` (live target; re-add to encrypted source after)
- Modify: `~/.local/share/chezmoi/dot_config/zsh/general.zsh`

**Interfaces:**
- Consumes: `completions.zsh` (Task 1) and `zinit cdreplay -q` (Task 2).
- Produces: final wired-up state.

- [ ] **Step 1: Add the `source` line to `~/.zshrc`**

Edit the live `~/.zshrc`. Find:

```zsh
# Zinit plugins
source "$ZSH_DIR/plugins.zsh"
```

Replace with:

```zsh
# Zinit plugins
source "$ZSH_DIR/plugins.zsh"

# Completions: the compinit engine lives in launch.zsh; plugin completions +
# `zinit cdreplay` live in plugins.zsh; tool/custom completions + styling live
# in completions.zsh (sourced here, after plugins so cdreplay has already run).
source "$ZSH_DIR/completions.zsh"
```

- [ ] **Step 2: Delete the terraform / `_git-ship` / `_gwtcd` / bun-completion block**

In `~/.zshrc`, delete this entire block (the terraform completion through the bun *completion* source — but KEEP the `# bun` / `export BUN_INSTALL` / `path_prepend` lines that follow it):

```zsh
# Defer bashcompinit + terraform completion until first use
# terraform() {
# unfunction terraform
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform
# terraform "$@"
# }

# Completion for `git ship` alias (defined in ~/.gitconfig)
_git-ship() {
    _arguments '1: :__git_branch_names'
}

# Completion for gwtcd: list worktree basenames
_gwtcd() {
    local -a names
    names=(${(f)"$(git worktree list 2>/dev/null | awk '{print $1}' | xargs -n1 basename)"})
    _describe 'worktree' names
}
compdef _gwtcd gwtcd

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
```

After deletion the `# bun` / `export BUN_INSTALL="$HOME/.bun"` / `path_prepend "$BUN_INSTALL/bin"` lines remain (they are PATH, not completion).

- [ ] **Step 3: Delete the `docker()` lazy-loader**

In `~/.zshrc`, delete:

```zsh
# Docker completion
docker () {
    unfunction docker
    FPATH="$HOME/.docker/completions:$FPATH"
    autoload -Uz compinit
    compinit
    docker "$@"
}
```

- [ ] **Step 4: Delete the terramate `complete -C` lines**

In `~/.zshrc`, delete:

```zsh
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terramate terramate
```

- [ ] **Step 5: Delete the labctl / jj per-startup completion sources**

In `~/.zshrc`, delete these two lines (KEEP the `path_append "/Users/zaid/.iximiuz/labctl/bin"` line just above them — it is PATH):

```zsh
source <(labctl completion zsh)
source <(jj util completion zsh)
```

- [ ] **Step 6: Remove the moved zstyles from `general.zsh`**

In `~/.local/share/chezmoi/dot_config/zsh/general.zsh`, delete the completion-config block (the 4 zstyle lines and their `# Completion Config` comment):

```zsh
# Completion Config
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' 
zstyle ':completion:*' list-colors '${(s.:.)LS_COLORS}'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
```

`general.zsh` now ends after the history config.

- [ ] **Step 7: Syntax-check both files**

Run:
```bash
zsh -n ~/.zshrc && zsh -n ~/.local/share/chezmoi/dot_config/zsh/general.zsh && echo OK
```
Expected: `OK`.

- [ ] **Step 8: Deploy general.zsh and re-encrypt .zshrc**

Run:
```bash
chezmoi apply ~/.config/zsh/general.zsh
chezmoi re-add ~/.zshrc
```
Then confirm the live `.zshrc` and the source agree (only the expected nonce diff in the .age blob):
```bash
cd ~/.local/share/chezmoi && chezmoi diff ~/.zshrc
```
Expected: no *content* differences when decrypted (a changed `.age` blob is normal).

- [ ] **Step 9: Verify a clean interactive start with no duplicate definitions**

Run:
```bash
zsh -ic exit 2>&1; echo "exit=$?"
```
Expected: no errors, `exit=0`.

- [ ] **Step 10: Verify each lazy completion registers on first use**

Run (each command once, then check a completion function is defined):
```bash
zsh -ic 'jj --version >/dev/null 2>&1; (( ${+functions[_jj]} )) && echo jj-ok'
zsh -ic 'labctl version >/dev/null 2>&1; (( ${+functions[_labctl]} )) && echo labctl-ok'
zsh -ic 'fpath=("$HOME/.docker/completions" $fpath); docker --version >/dev/null 2>&1; (( ${+functions[_docker]} )) || autoload -Uz _docker; echo docker-checked'
zsh -ic '_ensure_bashcompinit 2>/dev/null; type _ensure_bashcompinit >/dev/null && echo bashcompinit-fn-ok'
```
Expected: `jj-ok`, `labctl-ok`, and `bashcompinit-fn-ok` print. (terraform/terramate use `complete -C`, verified manually by tabbing in an interactive shell — see Step 12.)

- [ ] **Step 11: Compare startup time to the Task 1 baseline**

Run:
```bash
,zsh-bench 10
```
Expected: `Average:` is equal to or *lower* than the Task 1 baseline (labctl + jj no longer run at every startup). Note the result.

- [ ] **Step 12: Manual interactive smoke test**

Open a fresh interactive shell and confirm:
- `git ship <TAB>` offers branch names.
- `gwtcd <TAB>` offers worktree basenames.
- Run `terraform version` once, then `terraform <TAB>` completes subcommands.
- Run `terramate version` once, then `terramate <TAB>` completes.
- General tab-completion (e.g. `cd <TAB>` with fzf-tab preview) still works.

- [ ] **Step 13: Commit**

```bash
cd ~/.local/share/chezmoi
git add encrypted_dot_zshrc.age dot_config/zsh/general.zsh
git commit -m "refactor(zsh): move completions out of .zshrc into completions.zsh

Wire in completions.zsh, delete the .zshrc completion junk drawer
(terraform/terramate complete, docker lazy-loader, labctl/jj per-startup
sources, git-ship/gwtcd compdefs, bun completion) and the duplicate
completion zstyles in general.zsh. bashcompinit now runs once, lazily.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- New `completions.zsh` with header docs, helpers, zstyles, custom compdefs, lazy tools → Task 1. ✓
- `zinit cdreplay -q` in `plugins.zsh` → Task 2. ✓
- Remove zstyles from `general.zsh` → Task 3 Step 6. ✓
- Strip `.zshrc` junk drawer + add source line → Task 3 Steps 1-5. ✓
- Double `bashcompinit` fixed (now single guarded `_ensure_bashcompinit`) → Task 1 helper + Task 3 deletions. ✓
- docker no longer full-`compinit` → Task 1 docker line (autoload + compdef). ✓
- labctl/jj no longer per-startup → Task 1 lazy lines + Task 3 Step 5 deletion. ✓
- Docs/comments on `.zshrc` and `completions.zsh` → Task 1 header + Task 3 Step 1 comment + Task 2 cdreplay comment. ✓
- Out-of-scope items (PATH, ssh(), kubectl/gcloud, launch.zsh) left untouched. ✓
- Verification via `,zsh-bench` + manual checks (no test framework) → Task 1 Step 1 baseline, Task 3 Steps 9-12. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full content; every command has expected output.

**Type/name consistency:** `_lazy_completion`, `_ensure_bashcompinit`, `_lazy_bashcompinit`, `_git-ship`, `_gwtcd` used identically across Tasks 1 and 3. Function-existence checks use `_jj`/`_labctl`/`_docker` (the completion-function names those tools install).
