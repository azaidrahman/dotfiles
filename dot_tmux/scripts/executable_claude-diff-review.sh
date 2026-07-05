#!/usr/bin/env bash
# prefix+e launcher: open an oil.nvim-style directory browser (dir-picker-hunk.sh)
# in a popup, rooted at the active pane's cwd, to navigate to a worktree (or any
# directory) and review its working-tree changes with `hunk diff`. Invoked via
# run-shell so tmux expands the #{...} format into the args below.
#
# Why always the browser, never a straight `hunk diff`: the common setup is a
# shell sitting at a repo's BASE while an agent edits inside a linked worktree
# (under .worktrees/). The changes you want to see are in the worktree, not the
# base — so you need to navigate there first. Opening hunk directly on the base
# would trap you on the base's diff (and an untracked worktree dir can make the
# base look "dirty" even when it isn't your work). From the browser, "." on the
# base itself still gives the base's own diff in one keypress, so nothing is lost.
#
# hunk auto-reloads as the working tree changes, so the popup stays live while
# an agent keeps editing. Claude drives the same live session via
# `hunk session ...` (see the bundled hunk-review skill).
#
# $1 — pane current path (where the browser starts).
# $2 — pane id (where to `cd` once the browser accepts a directory).
set -euo pipefail

cwd=${1:?pane path required}
pane_id=${2:?pane id required}

# No tty is attached under plain run-shell, so the fzf browser needs
# display-popup to get one (see hold() in pane-md-preview.sh).
tmux display-popup -E -w 80% -h 80% -d "$cwd" -T ' cd → hunk diff ' \
  -- ~/.tmux/scripts/dir-picker-hunk.sh "$pane_id"
