#!/bin/bash
# prefix+e launcher: open the diff-review popup when the active pane's cwd is a
# git work tree. Invoked via run-shell so tmux expands the #{...} formats into
# the args below; we pass plain shell variables to display-popup (avoids fragile
# format-expansion / nested quoting inside an if-shell command arg).
# Args: 1=pane id (origin, for paste-back at confirm), 2=pane current path.
pane="${1:?}"
cwd="${2:?}"

# Always open the popup; the init decides what to show. If this repo has
# working-tree changes it opens the diff; if not (clean repo, or not a repo at
# all) it drops into a zoxide repo picker so prefix+e is never a confusing empty
# popup or a dead end.
tmux display-popup -E -w 90% -h 90% -d "$cwd" \
  -e "ORIGIN_PANE=$pane" -e "REPO=$cwd" \
  "nvim -u $HOME/.tmux/scripts/claude-diff-review-init.lua"
