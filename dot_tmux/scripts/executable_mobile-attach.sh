#!/usr/bin/env bash
# Attach to (or create) the "mobile" tmux session with a simplified,
# ASCII-only status bar suitable for Termius / small-screen iOS terminals.
# The session lives on the main tmux server, so windows can be link-window'd
# in from other sessions if desired.

SESSION="mobile"

# Create session if it doesn't exist yet. -A = attach if exists.
# Use shell command so we can apply per-session overrides before attaching.
if ! tmux has-session -t="$SESSION" 2>/dev/null; then
  tmux new-session -d -s "$SESSION"
fi

# --- Per-session overrides (do not use -g so these stay scoped to mobile) ---
# Strip the tokyo-night powerline widgets; use short ASCII status.
tmux set -t "$SESSION" status-left  "[#S] "
tmux set -t "$SESSION" status-right "#{?client_prefix,^ ,}#(date '+%a %d %b %H:%M') "
tmux set -t "$SESSION" status-left-length  20
tmux set -t "$SESSION" status-right-length 40
tmux set -t "$SESSION" status-style        "fg=white,bg=black"
tmux set -t "$SESSION" window-status-format         " #I:#W "
tmux set -t "$SESSION" window-status-current-format "[#I:#W]"
tmux set -t "$SESSION" window-status-current-style  "fg=black,bg=cyan,bold"
tmux set -t "$SESSION" window-status-separator      ""

# Quieter pane borders (no custom colors that may render oddly)
tmux set -t "$SESSION" pane-border-style        "fg=white"
tmux set -t "$SESSION" pane-active-border-style "fg=cyan"

# Drop the Ghostty-tuned dim-inactive-pane backgrounds (look wrong on Termius)
tmux set -u -t "$SESSION" window-style
tmux set -u -t "$SESSION" window-active-style

# Make this session track the latest client's size so the iPhone doesn't
# fight any desktop client that may attach to a different session.
tmux set -t "$SESSION" aggressive-resize on

exec tmux attach-session -t "$SESSION"
