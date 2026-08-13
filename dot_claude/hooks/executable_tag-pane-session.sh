#!/usr/bin/env bash
# Claude Code hook: tag this tmux pane with its own session identity.
#
# Wired to SessionStart, Stop, and SessionEnd. Two consumers, two mechanisms:
#
# 1. A per-pane tmux option (@claude_transcript), read by fork-claude-pane.sh
#    (prefix+| / prefix+_) to know which session runs in the pane you forked.
#    That script used to guess by taking the newest *.jsonl mtime under
#    ~/.claude/projects/<cwd>/ — which breaks as soon as two Claude panes share
#    the same project directory, since typing in EITHER pane bumps its mtime and
#    can make it look "newest" regardless of which pane you pressed the key in.
#
# 2. A file under ~/.local/state/claude-resurrect/, read by claude-resurrect
#    after tmux-resurrect restores a dead session. A tmux option cannot serve
#    here: resurrect saves a fixed set of pane fields and drops custom options,
#    so the identity must survive on disk. The file is keyed by the pane
#    coordinates that resurrect DOES preserve — session name, window index, and
#    pane index — because the restored pane has no other link to its past self.
#
# The hook payload carries this session's real session_id and transcript_path,
# and $TMUX_PANE is inherited from the pane's own process tree, so both records
# are exact rather than inferred.
#
# Why all three events. SessionStart alone is not enough: the session id changes
# on /clear, on compact, and on a forked resume, and the pane coordinates change
# whenever you move a pane between windows. Stop refreshes both on every turn,
# so the record stays current. SessionEnd captures the final id on a clean exit.
# A crash or a power loss fires nothing, which is exactly why Stop carries the
# weight — the last completed turn is already on disk when the machine dies.
#
# Idempotent: every event just overwrites.
set -euo pipefail

[ -n "${TMUX_PANE:-}" ] || exit 0

INPUT=$(cat 2>/dev/null || true)

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)

[ -n "$TRANSCRIPT" ] && tmux set-option -p -t "$TMUX_PANE" @claude_transcript "$TRANSCRIPT" 2>/dev/null

# --- resurrect record ---------------------------------------------------------

# Nothing to resume without an id, and no way to key the record outside tmux.
[ -n "$SESSION_ID" ] || exit 0

STATE_DIR="${CLAUDE_RESURRECT_STATE_DIR:-$HOME/.local/state/claude-resurrect}"

# Ask tmux about *this* pane. A bare `display-message -p` reports the attached
# client's active window, which is whatever the user happens to be looking at.
coords=$(tmux display-message -p -t "$TMUX_PANE" \
    '#{session_name}#{l:|}#{window_index}#{l:|}#{pane_index}#{l:|}#{@claude_base}' 2>/dev/null) || exit 0
IFS='|' read -r sname widx pidx label <<<"$coords"
[ -n "$sname" ] && [ -n "$widx" ] && [ -n "$pidx" ] || exit 0

# Session names are user-chosen and may hold path separators, so squeeze
# everything that is not alphanumeric into an underscore before using the name
# as part of a filename.
safe_sname=$(printf '%s' "$sname" | tr -c 'A-Za-z0-9_-' '_')
KEY="${safe_sname}__${widx}__${pidx}"

[ -n "$CWD" ] || CWD=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}' 2>/dev/null || true)
[ -n "$label" ] || label=$(tmux display-message -p -t "$TMUX_PANE" '#{window_name}' 2>/dev/null || true)

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Write to a temporary file and rename, so a reader never sees a half-written
# record. The temporary file carries the pid to keep concurrent panes apart.
tmp="$STATE_DIR/.$KEY.$$"
{
    printf 'session_id=%s\n' "$SESSION_ID"
    printf 'transcript=%s\n' "$TRANSCRIPT"
    printf 'cwd=%s\n' "$CWD"
    printf 'label=%s\n' "$label"
} >"$tmp" 2>/dev/null && mv -f "$tmp" "$STATE_DIR/$KEY" 2>/dev/null || rm -f "$tmp" 2>/dev/null

# Drop records that no longer describe anything. A pane that moved leaves its old
# coordinates behind, and that stale file would otherwise offer the wrong session
# to whichever pane lands there next. claude-resurrect also checks the directory
# before it trusts a record, so this is the second of two defences.
find "$STATE_DIR" -maxdepth 1 -type f -mtime +30 -delete 2>/dev/null || true

exit 0
