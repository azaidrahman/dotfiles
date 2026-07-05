#!/usr/bin/env bash
# SessionStart hook: tag this tmux pane with its own transcript path.
#
# fork-claude-pane.sh (prefix+| / prefix+_) needs to know exactly which Claude
# session is running in the pane it's forking. It used to guess by taking the
# newest *.jsonl mtime under ~/.claude/projects/<cwd>/ — which breaks as soon
# as two Claude panes share the same project directory, since typing in
# EITHER pane bumps its mtime and can make it look "newest" regardless of
# which pane you actually pressed the key in.
#
# The hook payload carries this session's real transcript_path, and $TMUX_PANE
# is inherited from the pane's own process tree, so we can tag the pane
# directly with a per-pane option instead of guessing. Runs on every
# SessionStart (including resume/compact/clear) — idempotent, just overwrites.
set -euo pipefail

[ -n "${TMUX_PANE:-}" ] || exit 0

INPUT=$(cat 2>/dev/null || true)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

[ -n "$TRANSCRIPT" ] && tmux set-option -p -t "$TMUX_PANE" @claude_transcript "$TRANSCRIPT" 2>/dev/null

exit 0
