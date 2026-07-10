#!/usr/bin/env bash
# prefix+e launcher: review the active pane's working-tree changes with `hunk`.
# Invoked via run-shell so tmux expands the #{...} format into the args below.
#
# If the pane's own cwd has uncommitted changes, open `hunk diff` on it
# directly — no detour. Otherwise (clean tree, or not a repo) fall back to an
# oil.nvim-style directory browser (dir-picker-hunk.sh) to find where the
# changes actually are — the common case being a shell sitting at a repo's
# BASE while an agent edits inside a linked worktree (under .worktrees/): the
# base looks clean, so we browse to the worktree instead of trapping you on an
# empty diff.
#
# hunk auto-reloads as the working tree changes, so the popup stays live while
# an agent keeps editing. Claude drives the same live session via
# `hunk session ...` (see the bundled hunk-review skill).
#
# $1 — pane current path (where the check/browser starts).
# $2 — pane id (where to `cd` once the browser accepts a directory).
set -euo pipefail

cwd=${1:?pane path required}
pane_id=${2:?pane id required}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/git-popup-size.sh"

# No tty is attached under plain run-shell, so both hunk and the fzf browser
# need display-popup to get one (see hold() in pane-md-preview.sh).
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 \
  && [[ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]]; then
  tmux display-popup -E -w "$POPUP_W" -h "$POPUP_H" -d "$cwd" -T ' hunk diff ' \
    -- hunk diff
else
  tmux display-popup -E -w "$POPUP_W" -h "$POPUP_H" -d "$cwd" -T ' cd → hunk diff ' \
    -- ~/.tmux/scripts/dir-picker-hunk.sh "$pane_id"
fi
