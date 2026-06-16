#!/usr/bin/env bash
# rename-tmux-window.sh — claim THIS Claude pane's tmux window name, deterministically.
#
# Given a final, already-decided name, this does the mechanical tmux dance that the
# skill's "Common mistakes" warn about, so it can't be gotten wrong:
#   - targets $TMUX_PANE (Claude's own pane), never the attached client's active window
#   - preserves any leading status glyph (●/⚠/⏸/✓) the notify-tmux.sh hook set
#   - sets @claude_base   so the glyph hook re-renders from the right base name
#   - sets @claude_autoname_done so the stop-time auto-namer stands down
#
# It does NOT decide the name (literal vs ticket, label squeezing, Jira lookup) —
# that judgment stays with the caller. Pass the finished name as the only argument.
#
# Usage:  rename-tmux-window.sh "<name>"
# stdout: "renamed: <glyph> <name>"
# Exit:   0 ok | 2 not in tmux / no pane / no name
set -euo pipefail

NAME=${1:-}
[ -n "$NAME" ]          || { echo "usage: $0 \"<name>\"" >&2; exit 2; }
[ -n "${TMUX:-}" ]      || { echo "not inside tmux (\$TMUX unset)" >&2; exit 2; }
PANE=${TMUX_PANE:-}
[ -n "$PANE" ]          || { echo "\$TMUX_PANE unset — cannot target Claude's window" >&2; exit 2; }

WID=$(tmux display-message -p -t "$PANE" '#{window_id}')
CUR=$(tmux display-message -p -t "$PANE" '#{window_name}')
GLYPH=$(printf '%s' "$CUR" | grep -oE '^[●⚠⏸✓]' || true)

tmux set-option -w -t "$WID" @claude_base "$NAME"
tmux set-option -w -t "$WID" @claude_autoname_done 1
tmux rename-window -t "$WID" "${GLYPH:+$GLYPH }$NAME"

echo "renamed: ${GLYPH:+$GLYPH }$NAME"
