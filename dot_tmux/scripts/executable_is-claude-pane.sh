#!/bin/bash
# Exit 0 if a `claude` process is running on the given tty, else exit 1.
# Used by the prefix+e diff-review binding to gate the popup to Claude panes.
# Arg 1: a tty, with or without the /dev/ prefix (tmux #{pane_tty} form).
tty="${1#/dev/}"
[ -z "$tty" ] && exit 1
ps -t "$tty" -o command= 2>/dev/null | grep -q '[c]laude'
