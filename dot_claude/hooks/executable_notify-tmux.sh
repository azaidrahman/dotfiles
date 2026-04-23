#!/usr/bin/env bash
# Claude Code notification hook — dispatched by event name ($1).
# Wired from ~/.claude/settings.json Notification/Stop hooks.
set -u

EVENT="${1:-}"
SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo 'unknown')
WINDOW=$(tmux display-message -p '#{window_index}' 2>/dev/null || echo '0')
WNAME=$(tmux display-message -p '#{window_name}' 2>/dev/null || echo 'claude')
LOGO="$HOME/.claude/claude-logo.png"
LOG_ALERT="$HOME/.tmux/scripts/log-alert.sh"

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
    permission_prompt)
        MSG=$(read_message)
        notify "${MSG:-Permission requested}"
        ;;
    idle_prompt)
        MSG=$(read_message)
        notify "${MSG:-Claude is idle}"
        alert_tmux
        ;;
    stop)
        notify 'Claude finished'
        alert_tmux
        ;;
    *)
        echo "notify-tmux.sh: unknown event '$EVENT'" >&2
        ;;
esac

exit 0
