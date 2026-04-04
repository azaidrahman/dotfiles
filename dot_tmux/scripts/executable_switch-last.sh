#!/bin/bash
# Switch to the last focused window/session — whatever was active last.
# Falls back to switch-client -l if no history or target was closed.

LAST=$(tmux show -gv @last_focus 2>/dev/null || true)

if [ -z "$LAST" ]; then
    tmux switch-client -l
    exit 0
fi

# Verify the window still exists
if ! tmux display -t "$LAST" -p '#{window_id}' >/dev/null 2>&1; then
    tmux switch-client -l
    exit 0
fi

TARGET_SESSION=$(tmux display -t "$LAST" -p '#{session_name}')
CURRENT_SESSION=$(tmux display -p '#{session_name}')

if [ "$TARGET_SESSION" != "$CURRENT_SESSION" ]; then
    tmux switch-client -t "$LAST"
else
    tmux select-window -t "$LAST"
fi
