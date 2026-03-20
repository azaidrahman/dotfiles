#!/bin/bash
zoomed=$(tmux display-message -p '#{window_zoomed_flag}')
original_fmt=$(tmux show -gv window-status-current-format)

if [ "$zoomed" -eq 1 ]; then
    # Save original if not already zoomed (check if green isn't already applied)
    if echo "$original_fmt" | grep -q '#73daca'; then
        tmux set -g @zoom-saved-fmt "$original_fmt"
    fi
    saved=$(tmux show -gv @zoom-saved-fmt 2>/dev/null)
    if [ -n "$saved" ]; then
        # Green bg, black text/icons
        modified=$(echo "$saved" | sed 's/#414868/#5fff00/g; s/#73daca/#000000/g; s/#a9b1d6/#000000/g')
        tmux set -g window-status-current-format "$modified"
    fi
else
    saved=$(tmux show -gv @zoom-saved-fmt 2>/dev/null)
    if [ -n "$saved" ]; then
        tmux set -g window-status-current-format "$saved"
    fi
fi
