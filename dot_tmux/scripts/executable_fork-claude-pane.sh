#!/usr/bin/env bash
# Fork the Claude or Pi *conversation* running in a given tmux pane into a new pane.
# Triggered by tmux bindings | (side-by-side) and _ (below). Runs OUTSIDE the
# process, so session environment variables are unavailable — the session is
# derived from the pane's cwd.
#
# Args: 1=origin pane id  2=pane cwd  3=pane tty  4=split dir (h|v)
set -euo pipefail

PANE="${1:?pane id required}"
CWD="${2:?cwd required}"
TTY="${3:?tty required}"
DIR="${4:-h}"

# 1. Gate: the origin pane must be running a `claude` or `pi` process.
tty="${TTY#/dev/}"
[ -z "$tty" ] && exit 1

CMD=$(ps -t "$tty" -o command= 2>/dev/null || true)

if echo "$CMD" | grep -q '[c]laude'; then
	AGENT="claude"
elif echo "$CMD" | grep -qw 'pi'; then
	AGENT="pi"
else
	tmux display-message "fork: not a Claude or Pi pane"
	exit 0
fi

# 2. Resolve the session id/file.
if [ "$AGENT" = "claude" ]; then
	# Prefer the transcript path the SessionStart hook tagged directly onto this
	# pane (see tag-pane-session.sh) — it names the exact session running here.
	# Falls back to newest-mtime under the cwd's project dir, which is only a
	# guess: it breaks when multiple Claude panes share the same project dir,
	# since typing in ANY of them can make its file look "newest".
	TRANSCRIPT=$(tmux show-options -pqv -t "$PANE" @claude_transcript 2>/dev/null || true)
	if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
		SID=$(basename "$TRANSCRIPT" .jsonl)
	else
		PROJ=$(printf '%s' "$CWD" | tr '/.' '--')
		NEWEST=$(ls -t "$HOME/.claude/projects/${PROJ}/"*.jsonl 2>/dev/null | head -1 || true)
		SID=$(basename "${NEWEST:-}" .jsonl)
	fi
	if [ -z "$SID" ]; then
		tmux display-message "fork: no Claude session for this dir"
		exit 0
	fi

	# Command to run in the new pane
	FORK_CMD="claude --resume $SID --fork-session"
	# Last 5 chars, matching the "id:" segment in statusline.sh.
	TITLE="fork:${SID: -5}"
	DISPLAY_NAME="${SID: -5}"
else
	# For Pi
	# Clean leading slash/backslash
	cleaned=$(echo "$CWD" | sed 's|^[/\]*||')
	# Replace /, \, and : with -
	safePath="--$(echo "$cleaned" | sed 's|[/\\:]|-|g')--"
	SESS_DIR="$HOME/.pi/agent/sessions/${safePath}"

	NEWEST=$(ls -t "${SESS_DIR}/"*.jsonl 2>/dev/null | head -1 || true)
	if [ -z "$NEWEST" ]; then
		tmux display-message "fork: no Pi session for this dir"
		exit 0
	fi

	SID=$(basename "$NEWEST" .jsonl)
	# Extract the UUID part after the last _
	UUID="${SID##*_}"

	# Command to run in the new pane
	FORK_CMD="pi --fork \"$NEWEST\""
	TITLE="fork:${UUID:0:8}"
	DISPLAY_NAME="${UUID:0:8}"
fi

# 3. Split a detached pane from the origin and fork the session into it.
SPLIT="-h"
[ "$DIR" = "v" ] && SPLIT="-v"
NEW=$(tmux split-window "$SPLIT" -d -c "$CWD" -t "$PANE" -P -F '#{pane_id}')
tmux send-keys -t "$NEW" "$FORK_CMD" Enter
tmux select-pane -t "$NEW" -T "$TITLE"

# 4. Report (no Claude/Pi relays output now).
tmux display-message "forked ${DISPLAY_NAME} → $NEW"
