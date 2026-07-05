#!/usr/bin/env bash
# prefix+e launcher: open `hunk diff` in a popup to review the working-tree
# changes of the active pane's repo. Invoked via run-shell so tmux expands the
# #{...} format into the arg below.
#
# hunk auto-reloads as the working tree changes, so the popup stays live while
# an agent keeps editing in another pane. Claude drives the same live session
# via `hunk session ...` (see the bundled hunk-review skill).
#
# Clean repo, or not a repo: falls back to an fzf picker over subdirectories of
# the pane's cwd (e.g. sibling worktrees under .worktrees/) so you can jump to
# one and try hunk diff there, instead of opening an empty hunk session.
#
# $1 — pane current path (where to look for changes / open hunk / start the picker).
# $2 — pane id (where to `cd` if the fallback picker picks a directory).
set -euo pipefail

cwd=${1:?pane path required}
pane_id=${2:?pane id required}

# True when $1 is inside a git work tree that has changes (tracked or untracked).
has_changes() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [[ -n $(git -C "$1" status --porcelain 2>/dev/null) ]]
}

open_hunk() {
  tmux display-popup -E -w 96% -h 96% -d "$1" -- hunk diff
}

# No tty is attached under plain run-shell, so an fzf/select picker needs
# display-popup to get one (see hold() in pane-md-preview.sh) — that's also
# what the dir picker below relies on.
open_dir_picker() {
  tmux display-popup -E -w 80% -h 80% -d "$1" -T ' cd → hunk diff ' \
    -- ~/.tmux/scripts/dir-picker-hunk.sh "$2"
}

if has_changes "$cwd"; then
  open_hunk "$cwd"
else
  open_dir_picker "$cwd" "$pane_id"
fi
