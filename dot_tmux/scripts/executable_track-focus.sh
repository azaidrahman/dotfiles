#!/bin/bash
# Track window/session changes for "last active anything" switching
# Called from after-select-window and client-session-changed hooks

NEW="$1"
CURRENT=$(tmux show -gv @current_focus 2>/dev/null || true)

if [ -n "$CURRENT" ] && [ "$CURRENT" != "$NEW" ]; then
    tmux set -g @last_focus "$CURRENT"
fi
tmux set -g @current_focus "$NEW"
