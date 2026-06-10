#!/bin/bash
session="$1"
window="$2"
echo "$(date '+%H:%M:%S') clear-alert called: session=$session window=$window" >> ~/.tmux/alert-debug.log
terminal-notifier -remove "claude-${session}" &
# Only clear the specific window you focused, not the whole session
sed -i '' "/^${session}:${window}\t/d" ~/.tmux/alerts 2>/dev/null
