#!/usr/bin/env bash
# Fork the current Claude *conversation* into a new tmux pane.
# Same dir, same branch — only the session is forked. Current pane stays
# attached to the original session, untouched.
#
# Usage: branch-pane.sh [v]    # pass "v" for a vertical (below) split; default horizontal
set -euo pipefail

# 1. Must be inside tmux
if [ -z "${TMUX:-}" ]; then
  echo "branch-pane: not inside tmux — nothing to do." >&2
  exit 1
fi

# 2. Find the current session id (Claude Code exports it; fall back to newest
#    session file for this project directory just in case it's unset).
SID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$SID" ]; then
  PROJ=$(printf '%s' "$PWD" | tr '/.' '--')
  NEWEST=$(ls -t "$HOME/.claude/projects/${PROJ}/"*.jsonl 2>/dev/null | head -1 || true)
  SID=$(basename "${NEWEST:-}" .jsonl)
fi
if [ -z "$SID" ]; then
  echo "branch-pane: couldn't determine the current session id." >&2
  exit 1
fi

# 3. Open a new pane (unfocused) in the same dir, resume + fork the session there.
SPLIT="-h"; [ "${1:-}" = "v" ] && SPLIT="-v"
NEW=$(tmux split-window "$SPLIT" -d -c "$PWD" -P -F '#{pane_id}')
tmux send-keys -t "$NEW" "claude --resume $SID --fork-session" Enter
tmux select-pane -t "$NEW" -T "fork:${SID:0:8}"

# 4. Report
printf 'Forked session : %s\nNew pane       : %s (claude resuming a fork)\nThis pane      : unchanged (original session)\n' "$SID" "$NEW"
