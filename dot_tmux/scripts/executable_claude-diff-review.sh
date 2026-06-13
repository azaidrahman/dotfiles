#!/bin/bash
# prefix+e launcher: open the Claude diff-review popup if the active pane is
# running Claude. Invoked via run-shell so tmux expands the #{...} formats into
# the args below; we then pass plain shell variables to display-popup (avoids
# fragile format-expansion / nested quoting inside an if-shell command arg).
# Args: 1=pane id, 2=pane tty, 3=pane current path.
pane="${1:?}"
tty="${2:?}"
cwd="${3:?}"

# Gate to Claude panes; silently no-op otherwise.
"$HOME/.tmux/scripts/is-claude-pane.sh" "$tty" || exit 0

tmux display-popup -E -w 90% -h 90% -d "$cwd" \
  -e "CLAUDE_PANE=$pane" -e "REPO=$cwd" \
  "nvim -u $HOME/.tmux/scripts/claude-diff-review-init.lua"
