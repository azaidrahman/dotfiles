#!/usr/bin/env bash
# prefix+e launcher: open `hunk diff` in a popup to review the working-tree
# changes of the active pane's repo. Invoked via run-shell so tmux expands the
# #{...} format into the arg below.
#
# hunk auto-reloads as the working tree changes, so the popup stays live while
# an agent keeps editing in another pane. Claude drives the same live session
# via `hunk session ...` (see the bundled hunk-review skill).
#
# $1 — pane current path (where to look for changes / open hunk).
set -euo pipefail

cwd=${1:?pane path required}

# True when $1 is inside a git work tree that has changes (tracked or untracked).
has_changes() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [[ -n $(git -C "$1" status --porcelain 2>/dev/null) ]]
}

open_hunk() {
  tmux display-popup -E -w 90% -h 90% -d "$1" -- hunk diff
}

# Repo with changes under the cursor: review it directly.
if has_changes "$cwd"; then
  open_hunk "$cwd"
  exit 0
fi

# Clean repo, or not a repo: fall back to a zoxide frecency picker so prefix+e
# is never a confusing empty popup or a dead end. Mirrors md-pick.sh's fzf/menu
# pattern. Cancelling exits cleanly.
mapfile -t dirs < <(zoxide query --list 2>/dev/null || true)
(( ${#dirs[@]} == 0 )) && { tmux display-message "diff-review: no changes here, and zoxide has no repos"; exit 0; }

if command -v fzf >/dev/null; then
  target=$(printf '%s\n' "${dirs[@]}" | fzf --reverse --prompt='review repo > ' \
    --preview='git -C {} status --short 2>/dev/null || echo "not a git repo"' \
    --preview-window='right:60%') || exit 0
else
  PS3=$'\nPick a repo (number, Ctrl-C to cancel): '
  select target in "${dirs[@]}"; do
    [[ -n ${target:-} ]] && break
  done
fi
[[ -z ${target:-} ]] && exit 0

open_hunk "$target"
