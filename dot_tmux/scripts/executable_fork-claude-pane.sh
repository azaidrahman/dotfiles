#!/usr/bin/env bash
# Fork the Claude *conversation* running in a given tmux pane into a new pane.
# Triggered by tmux bindings | (side-by-side) and _ (below). Runs OUTSIDE the
# Claude process, so $CLAUDE_CODE_SESSION_ID is unavailable — the session id is
# derived from the pane's cwd (newest session .jsonl by mtime).
#
# Args: 1=origin pane id  2=pane cwd  3=pane tty  4=split dir (h|v)
set -euo pipefail

PANE="${1:?pane id required}"
CWD="${2:?cwd required}"
TTY="${3:?tty required}"
DIR="${4:-h}"

# 1. Gate: the origin pane must be running a `claude` process.
tty="${TTY#/dev/}"
if [ -z "$tty" ] || ! ps -t "$tty" -o command= 2>/dev/null | grep -q '[c]laude'; then
  tmux display-message "fork: not a Claude pane"
  exit 0
fi

# 2. Resolve the session id from the cwd's project dir (newest .jsonl by mtime).
PROJ=$(printf '%s' "$CWD" | tr '/.' '--')
NEWEST=$(ls -t "$HOME/.claude/projects/${PROJ}/"*.jsonl 2>/dev/null | head -1 || true)
SID=$(basename "${NEWEST:-}" .jsonl)
if [ -z "$SID" ]; then
  tmux display-message "fork: no session for this dir"
  exit 0
fi

# 3. Split a detached pane from the origin and fork the session into it.
SPLIT="-h"; [ "$DIR" = "v" ] && SPLIT="-v"
NEW=$(tmux split-window "$SPLIT" -d -c "$CWD" -t "$PANE" -P -F '#{pane_id}')
tmux send-keys -t "$NEW" "claude --resume $SID --fork-session" Enter
tmux select-pane -t "$NEW" -T "fork:${SID:0:8}"

# 4. Report (no Claude relays output now).
tmux display-message "forked ${SID:0:8} → $NEW"
