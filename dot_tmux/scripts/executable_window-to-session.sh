#!/bin/bash
# Move the current tmux window into a session, creating it if it doesn't exist.
# A new session is born with a placeholder window; we move ours in and kill it,
# so the new session ends up holding only the window we moved.

name="$1"
[ -z "$name" ] && exit 0

win=$(tmux display-message -p '#{window_id}')

if tmux has-session -t "=$name" 2>/dev/null; then
    tmux move-window -s "$win" -t "$name":
else
    tmux new-session -d -s "$name"
    placeholder=$(tmux list-windows -t "=$name" -F '#{window_id}' | head -1)
    tmux move-window -s "$win" -t "$name":
    tmux kill-window -t "$placeholder"
fi

tmux switch-client -t "$name"
