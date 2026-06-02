#!/usr/bin/env bash
# Claude Code notification hook — dispatched by event name ($1).
# Wired from ~/.claude/settings.json Notification/Stop/UserPromptSubmit hooks.
set -u

EVENT="${1:-}"
SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo 'unknown')
WINDOW=$(tmux display-message -p '#{window_index}' 2>/dev/null || echo '0')
WIN_ID=$(tmux display-message -p '#{window_id}' 2>/dev/null || echo '')
WNAME=$(tmux display-message -p '#{window_name}' 2>/dev/null || echo 'claude')
LOGO="$HOME/.claude/claude-logo.png"
LOG_ALERT="$HOME/.tmux/scripts/log-alert.sh"

# Prefix a status glyph to the current window name, reflecting Claude's state.
# The original name is captured once into @claude_base so the glyph can cycle
# across events without losing the base name. No-op when not inside tmux.
window_status() {
    [ -n "$WIN_ID" ] || return 0
    local glyph="$1"
    local base
    base=$(tmux show-options -wqv -t "$WIN_ID" @claude_base 2>/dev/null)
    if [ -z "$base" ]; then
        base="$WNAME"
        tmux set-option -w -t "$WIN_ID" @claude_base "$base" 2>/dev/null
    fi
    tmux rename-window -t "$WIN_ID" "$glyph $base" 2>/dev/null || true
}

notify() {
    command -v terminal-notifier >/dev/null || return 0
    terminal-notifier \
        -title 'Claude Code' \
        -subtitle "Session: $SESSION" \
        -message "$1" \
        -contentImage "$LOGO" \
        -sound Glass \
        -group "claude-$SESSION" >/dev/null 2>&1 || true
}

alert_tmux() {
    [ -x "$LOG_ALERT" ] && "$LOG_ALERT" "$SESSION" "$WINDOW" "$WNAME" CLAUDE || true
}

read_message() {
    jq -r '.message // empty' 2>/dev/null || echo ""
}

case "$EVENT" in
    working)
        window_status '●'
        ;;
    permission_prompt)
        MSG=$(read_message)
        notify "${MSG:-Permission requested}"
        window_status '⚠'
        ;;
    idle_prompt)
        MSG=$(read_message)
        notify "${MSG:-Claude is idle}"
        window_status '⏸'
        alert_tmux
        ;;
    stop)
        notify 'Claude finished'
        window_status '✓'
        alert_tmux
        ;;
    *)
        echo "notify-tmux.sh: unknown event '$EVENT'" >&2
        ;;
esac

exit 0
