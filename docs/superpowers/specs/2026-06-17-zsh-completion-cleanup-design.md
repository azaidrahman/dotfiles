# Zsh Completion Cleanup — Design

**Date:** 2026-06-17
**Status:** Approved

## Problem

Completion configuration is scattered and partly broken across `~/.zshrc` and
`~/.config/zsh/*.zsh`. Symptoms:

1. **`bashcompinit` runs twice** in `.zshrc` (lines 64 & 124) — once for
   terraform, once for terramate.
2. **`docker()` lazy-loader runs a full `compinit`** (line 120) with no `-C` and
   no cache, defeating the careful cached `compinit` in `launch.zsh`.
3. **`labctl` and `jj` completions use `source <(<tool> completion zsh)`**
   (lines 128-129) — these execute the tool on *every* shell startup. Slow.
   `kubectl` already solved this; these didn't.
4. **Completion logic lives in `.zshrc`** at all, despite the config being
   organized into modular `$ZSH_DIR/*.zsh` files. The rc became a junk drawer as
   tools were bolted on.
5. **No `zinit cdreplay`** — turbo-deferred plugin completions
   (`zsh-completions`, `fzf-tab`) register `compdef`s *after* the early
   `compinit`, so without a replay they can land out of order or never activate.

## Goal

Consolidate all completion config into one well-documented module, fix the
init bugs, lazy-load slow tool completions, and add the missing zinit
`cdreplay` — while keeping the existing modular structure and turbo-loading
strategy intact.

## Architecture (mental model after cleanup)

| Concern | Owner | File |
|---|---|---|
| `compinit` (the engine) | you | `launch.zsh` (unchanged) |
| plugin completions + `cdreplay` | zinit | `plugins.zsh` |
| tool completions (lazy) + custom compdefs + styling | you | `completions.zsh` (new) |

`launch.zsh` already does the right thing for the engine: cached `.zcompdump`
with a 24h rebuild window and a `compinit -C` fast path. It is **not touched**.

## Changes

### 1. New file `~/.config/zsh/completions.zsh`

Sourced from `.zshrc` immediately after `plugins.zsh`. Internal order:

**Header block** documenting:
- the architecture map above
- how the lazy-load pattern works and its tradeoff (no arg-completion for a
  command until its first invocation in a session)
- a "how to add a new tool completion" recipe
- section dividers

**Helpers:**

```zsh
# Lazy-load a command's completion on first invocation.
#   $1 = command name, $2 = code that loads its completion
# On first run the wrapper removes itself, loads the completion, then execs
# the real command. Tradeoff: `<cmd> <TAB>` does nothing until you've run
# <cmd> once this session.
_lazy_completion() { eval "$1() { unfunction $1; $2; $1 \"\$@\"; }"; }

# Run bashcompinit at most once (needed by `complete -C` style tools).
_ensure_bashcompinit() {
  (( ${+_lazy_bashcompinit} )) && return
  autoload -U +X bashcompinit && bashcompinit
  _lazy_bashcompinit=1
}
```

**Completion styling** (`### styles`) — moved verbatim from `general.zsh`:

```zsh
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors '${(s.:.)LS_COLORS}'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
```

**Eager custom compdefs** (`### custom compdefs`) — cheap, relocated as-is:
- `_git-ship` function (git auto-discovers `_git-<sub>` for `git ship`)
- `_gwtcd` function + `compdef _gwtcd gwtcd`
- bun static source: `[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"`

**Lazy tool completions** (`### lazy tool completions`):

```zsh
_lazy_completion jj        'source <(jj util completion zsh)'
_lazy_completion labctl    'source <(labctl completion zsh)'
_lazy_completion docker    'fpath=("$HOME/.docker/completions" $fpath); autoload -Uz _docker && compdef _docker docker'
_lazy_completion terraform '_ensure_bashcompinit; complete -o nospace -C /opt/homebrew/bin/terraform terraform'
_lazy_completion terramate '_ensure_bashcompinit; complete -o nospace -C /opt/homebrew/bin/terramate terramate'
```

Note docker no longer re-runs `compinit` at all. The original full `compinit`
rebuild was heavy; `compinit -C` would be cheap but reads the cached dump and
would *not* pick up the freshly-added `~/.docker/completions` dir. Instead we
prepend that dir to `fpath`, autoload `_docker`, and register it with `compdef`
— light and correct.

### 2. `plugins.zsh`

Add at the end, with an explanatory comment:

```zsh
# Replay compdefs captured from turbo-deferred plugins (zsh-completions,
# fzf-tab) — they call compdef AFTER the early compinit in launch.zsh, so
# zinit queues those calls and cdreplay applies them in one pass.
zinit cdreplay -q
```

The kubectl/gcloud completions already in `plugins.zsh` stay as-is.

### 3. `general.zsh`

Remove the 4 completion `zstyle` lines (now in `completions.zsh`). File keeps
only `bindkey`, `setopt`, and history config.

### 4. `.zshrc`

Delete the completion junk drawer (current lines ~61-129 that relate to
completion): terraform/terramate `complete -C` + `bashcompinit`, `_git-ship`,
`_gwtcd`+`compdef`, bun source/completion, and the `docker()` lazy-loader,
plus the `source <(labctl …)` / `source <(jj …)` lines.

Replace with a single sourced module plus a short note comment:

```zsh
# Completions: the engine (compinit) is in launch.zsh; plugin completions +
# cdreplay are in plugins.zsh; tool/custom completions + styling live here.
source "$ZSH_DIR/completions.zsh"
```

**Kept in `.zshrc` (out of scope — not completion):** PATH helpers and PATH
manipulation, `BUN_INSTALL`, the homebrew/pyenv path reorder, and the `ssh()`
tmux-pane wrapper.

## Out of scope

- PATH management and the homebrew/pyenv reorder blocks
- The `ssh()` wrapper
- `kubectl`/`gcloud` completions already cleanly in `plugins.zsh`
- `launch.zsh`'s compinit engine

## Verification

- New shell starts without errors; startup is not slower (labctl/jj no longer
  run at startup).
- `bashcompinit` defined once; `complete -C` tools work after first invocation.
- `jj <TAB>` / `labctl <TAB>` / `docker <TAB>` / `terraform <TAB>` /
  `terramate <TAB>` complete correctly after running each command once.
- Plugin completions from `zsh-completions` are active (cdreplay working).
- `chezmoi apply` cleanly reproduces all changes (source files edited, not
  deployed copies).
