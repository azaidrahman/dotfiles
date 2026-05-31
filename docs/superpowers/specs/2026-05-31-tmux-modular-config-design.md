# tmux Modular Config — Design

**Date:** 2026-05-31
**Status:** Approved

## Problem

`dot_tmux.conf.tmpl` has grown to ~185 lines in a single file. It mixes options,
keybindings, plugin declarations, visual styling, and hooks. The visual styling is
scattered across the file (theme vars before TPM, style overrides after TPM), which
makes it hard to maintain and hard to strip out. A separate, brittle copy of the
"stripped" visual profile also lives inside `mobile-attach.sh`, so adding a visual
global means remembering to also un-set it in the shell script.

## Goals

1. Split the monolith into modular fragments in their own directory.
2. Isolate all visual styling so it can be removed cleanly.
3. Two independent ways to strip visuals:
   - **Host-level (deploy-time):** a host runs plain stock tmux.
   - **Per-session (runtime):** the mobile/Termius session is stripped while
     desktop clients on the same host keep full visuals.

## Non-goals

- Changing any keybindings, hooks, plugin set, or the aqua/onyx color theming.
- Pre-flagging any host as headless (aqua and onyx are both used interactively).

## Architecture

A `conf.d/` directory of fragments loaded by a thin **templated loader**
(`~/.tmux.conf`) using explicit `source-file` lines (not a `*.conf` glob, because
TPM ordering matters and the visual fragment must be conditionally skippable).

### File layout

`dot_tmux/conf.d/` → `~/.tmux/conf.d/`:

| File | Contents | Visual |
|------|----------|--------|
| `options.conf` | terminal/truecolor, general opts (clipboard, mouse, status-interval, detach-on-destroy, window-size, monitor-bell, bell-action), mode-keys, extended-keys, status-position | no |
| `keys.conf` | prefix + every keybinding + copy-mode bindings | no |
| `plugins.conf.tmpl` | PATH for tpm; functional plugins (tpm, sensible, vim-tmux-navigator, resurrect, continuum, tmux-jump) + continuum-restore; then — guarded by `$minimal` — the tokyo-night theme plugin + its vars; then `run tpm` | partly |
| `visual.conf.tmpl` | everything after TPM: pane-border styles, pane-border-status/format title bar, dim-inactive-pane window-style, the status-left/right widget `sed` overrides, the aqua/onyx hostname color block | yes |
| `visual-mobile.conf` | the `set -t mobile …` minimal profile, extracted out of `mobile-attach.sh` | yes (mobile) |
| `hooks.conf` | all `set-hook` lines (zoom-indicator, alert-bell, clear-alert, track-focus) | no |

The loader `dot_tmux.conf.tmpl` → `~/.tmux.conf` shrinks to ~10 lines of guarded
`source-file` calls.

### Load order (TPM boundary preserved)

```
options.conf
keys.conf
plugins.conf.tmpl      # declares plugins (theme only if !minimal), then runs tpm
visual.conf.tmpl       # sourced only if !minimal — runs AFTER tpm
hooks.conf
```

## The two strip mechanisms

### 1. Host-level toggle (deploy-time)

Top of the loader:

```go
{{ "{{-" }} $headless := list {{ "-}}" }}              // add hostnames here, e.g. (list "aqua")
{{ "{{-" }} $minimal := has .chezmoi.hostname $headless {{ "-}}" }}
```

When the host is in `$headless`: the loader skips `visual.conf` entirely and
`plugins.conf.tmpl` skips the theme plugin → plain stock tmux. The list is empty
today; add a hostname when a box should be stripped. No `.chezmoi.toml` change and
no re-prompt.

### 2. Per-session mobile (runtime)

`mobile-attach.sh` stops hardcoding its reset list and instead runs
`tmux source-file ~/.tmux/conf.d/visual-mobile.conf` after creating the `mobile`
session. All visual config now lives together in `conf.d/`, eliminating drift.
The existing zsh trigger (`LC_MOBILE=1` from Termius → `mobile-attach.sh`) is
unchanged.

## Behavior preserved

- `prefix-r` reload still works (re-sources the loader → re-sources fragments).
- TPM ordering, continuum auto-restore, all hooks, keybindings, and aqua/onyx
  theming unchanged.

## Verification

1. `chezmoi execute-template < dot_tmux.conf.tmpl` renders without error.
2. `chezmoi apply`, then `prefix-r`; confirm status bar / borders / pane titles /
   colors look identical to the pre-refactor state.
3. Launch the `mobile` session; confirm it is still stripped (ASCII status bar,
   no powerline, default pane colors).
