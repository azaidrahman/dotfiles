#!/bin/sh
# Auto-pick delta layout based on the CURRENT terminal width.
# Re-evaluated on every `git diff`/`show`/`log`/`blame`, so it adapts as
# tmux panes resize: side-by-side when there's room, unified when narrow.
#
# Threshold: side-by-side splits the width in two, so wide lines only stay
# unwrapped when each pane has room. 140 cols ≈ two ~68-char panes.
# delta.side-by-side defaults to false in git config; we add the flag only
# when the pane is wide enough, so plain `delta` stays unified.
cols=$(tput cols 2>/dev/null || echo 0)
if [ "$cols" -ge 140 ]; then
  exec delta --side-by-side
else
  exec delta
fi
