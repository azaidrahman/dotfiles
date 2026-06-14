#!/bin/bash
# prefix+e launcher: open the diff-review popup when the active pane's cwd is a
# git work tree. Invoked via run-shell so tmux expands the #{...} formats into
# the args below; we pass plain shell variables to display-popup (avoids fragile
# format-expansion / nested quoting inside an if-shell command arg).
# Args: 1=pane id (origin, for paste-back at confirm), 2=pane current path.
pane="${1:?}"
cwd="${2:?}"

# Gate on the presence of a git work tree; silently no-op otherwise.
git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Gate on there being something to review. With no working-tree changes codediff
# would open an empty "No changes to show" popup that looks like a blank nvim, so
# flash a message and skip opening it entirely.
if [ -z "$(git -C "$cwd" status --porcelain)" ]; then
  tmux display-message "diff-review: no changes to review"
  exit 0
fi

tmux display-popup -E -w 90% -h 90% -d "$cwd" \
  -e "ORIGIN_PANE=$pane" -e "REPO=$cwd" \
  "nvim -u $HOME/.tmux/scripts/claude-diff-review-init.lua"
