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

# Apply the minimal per-session visual profile. All overrides live in the conf
# fragment (scoped to `mobile`, so desktop clients are unaffected) — kept next
# to the full visual config in conf.d/ to avoid drift.
tmux source-file ~/.tmux/conf.d/visual-mobile.conf

exec tmux attach-session -t "$SESSION"
