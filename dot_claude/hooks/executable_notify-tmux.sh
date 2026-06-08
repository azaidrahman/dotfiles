#!/usr/bin/env bash
# Claude Code notification hook — dispatched by event name ($1).
# Wired from ~/.claude/settings.json Notification/Stop/UserPromptSubmit hooks.
set -u

EVENT="${1:-}"
PANE="${TMUX_PANE:-}"

# Query tmux about *this* Claude pane's window, not the attached client's active
# window. Bare `display-message -p` reports whatever window the user is currently
# looking at — if they've switched away, that's the wrong window. -t "$TMUX_PANE"
# always resolves to the pane this hook's process lives in.
tq() {
    if [ -n "$PANE" ]; then
        tmux display-message -p -t "$PANE" "$1" 2>/dev/null
    else
        tmux display-message -p "$1" 2>/dev/null
    fi
}

SESSION=$(tq '#{session_name}'); SESSION=${SESSION:-unknown}
WINDOW=$(tq '#{window_index}'); WINDOW=${WINDOW:-0}
WIN_ID=$(tq '#{window_id}')
WNAME=$(tq '#{window_name}'); WNAME=${WNAME:-claude}
LOGO="$HOME/.claude/claude-logo.png"
LOG_ALERT="$HOME/.tmux/scripts/log-alert.sh"

# Debug trace: export CLAUDE_TMUX_DEBUG=1 to log every event + autoname decision
# to ~/.claude/notify-tmux-debug.log, or set it to an explicit path. Off by
# default (empty), so this is zero-cost in normal use. `tail -f` it to watch
# exactly which turn autoname_capture fires on and why it bails when it doesn't.
DEBUG_LOG="${CLAUDE_TMUX_DEBUG:-}"
[ "$DEBUG_LOG" = "1" ] && DEBUG_LOG="$HOME/.claude/notify-tmux-debug.log"
dlog() {
    [ -n "$DEBUG_LOG" ] || return 0
    printf '%s [%-16s] win=%-4s %s\n' \
        "$(date '+%H:%M:%S')" "$EVENT" "${WIN_ID:-?}" "$1" >>"$DEBUG_LOG" 2>/dev/null || true
}

# Default window names Claude inherits before anything meaningful is set — these
# are fair game to auto-rename over. Anything else means the user named it.
is_default_name() {
    case "$1" in
        ''|zsh|-zsh|bash|-bash|sh|fish|node|claude|login) return 0 ;;
        *) return 1 ;;
    esac
}

# Compress a topic into a terse kebab-case label of the first $2 words. Purely
# local: lowercase, strip punctuation, collapse whitespace, then hard-cap to $2
# words. Deliberately no `claude -p` shortening pass — it added ~9s of latency on
# every `stop` for a marginally nicer label. The first-N-words truncation is
# instant and good enough since CC's own topics already lead with the essence.
kebab_short() {
    local t="$1" max="$2"
    printf '%s' "$t" \
        | tr 'A-Z' 'a-z' \
        | sed -E 's/[^a-z0-9 -]//g; s/[[:space:]]+/ /g; s/^ +//; s/ +$//' \
        | awk -v m="$max" '{ for (i = 1; i <= m && i <= NF; i++) printf (i > 1 ? "-" : "") $i }'
}

# Cheap, runs on every prompt: if this is the first touch of the window and it
# already carries a non-default custom name, the user set it themselves — claim
# @claude_autoname_done so we never auto-rename over their choice. Must run before
# window_status's first rename, while WNAME still reflects the pre-Claude name.
autoname_protect() {
    [ -n "$WIN_ID" ] || return 0
    [ -n "$(tmux show-options -wqv -t "$WIN_ID" @claude_autoname_done 2>/dev/null)" ] && { dlog "protect: already done"; return 0; }
    [ -n "$(tmux show-options -wqv -t "$WIN_ID" @claude_base 2>/dev/null)" ] && { dlog "protect: base already set"; return 0; }
    local stripped
    stripped=$(printf '%s' "$WNAME" | sed -E 's/^[^[:alnum:]]+[[:space:]]*//; s/[[:space:]]+$//')
    if is_default_name "$stripped"; then
        dlog "protect: default name [$stripped], leaving open for capture"
    else
        dlog "protect: custom name [$stripped] -> claim done, no auto-capture"
        tmux set-option -w -t "$WIN_ID" @claude_autoname_done 1 2>/dev/null
    fi
}

# Auto-name the window after Claude Code's generated conversation topic, once per
# window. CC emits that topic as the pane title (e.g. "⠂ Add window title hook…");
# we strip the leading spinner/glyph, compress it to <4 words (local kebab), and
# prepend the branch's Jira ticket if any, storing it as @claude_base so the glyph
# hook keeps it. Runs only on `stop` — the topic isn't generated until the first
# turn finishes. Gated by @claude_autoname_done so it only succeeds once per
# window, but bails WITHOUT claiming done while the topic is still unavailable, so
# it keeps retrying on later stops until CC has produced a real topic.
autoname_capture() {
    [ -n "$WIN_ID" ] || { dlog "capture: no WIN_ID"; return 0; }
    [ -n "$(tmux show-options -wqv -t "$WIN_ID" @claude_autoname_done 2>/dev/null)" ] && { dlog "capture: already done, skip"; return 0; }

    # Pull CC's topic from the pane title; drop a leading spinner/glyph + spaces.
    local raw topic
    raw=$(tq '#{pane_title}')
    topic=$(printf '%s' "$raw" | sed -E 's/^[^[:alnum:]]+[[:space:]]*//; s/[[:space:]]+$//')
    dlog "capture: raw=[$raw] topic=[$topic]"

    # Early on, the pane title is still a stale shell/command name. Require a real
    # multi-word topic; otherwise bail WITHOUT marking done so a later stop retries.
    case "$topic" in *' '*) : ;; *) dlog "capture: topic not multi-word, retry next stop"; return 0 ;; esac
    is_default_name "$topic" && { dlog "capture: topic is a default name, retry next stop"; return 0; }

    # Lead with the Jira ticket from the branch, mirroring the rename-tmux-window
    # skill, and keep the whole label under ~4 words (3 for the topic when a ticket
    # eats one).
    local path branch ticket max name
    path=$(tq '#{pane_current_path}')
    branch=$(git -C "${path:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)
    ticket=$(printf '%s' "$branch" | grep -oE '[A-Z]+-[0-9]+' | head -1)
    max=4; [ -n "$ticket" ] && max=3

    tmux set-option -w -t "$WIN_ID" @claude_autoname_done 1 2>/dev/null
    name="${ticket:+$ticket }$(kebab_short "$topic" "$max")"
    tmux set-option -w -t "$WIN_ID" @claude_base "$name" 2>/dev/null
    dlog "capture: SET base=[$name] (ticket=[$ticket] max=$max)"
}

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
    # Subtitle = session + the window's topic, so concurrent sessions are easy to
    # tell apart. Prefer @claude_base (the clean auto-named topic, no status glyph);
    # fall back to the window name with any leading glyph/spaces stripped.
    local label sub
    label=$(tmux show-options -wqv -t "$WIN_ID" @claude_base 2>/dev/null)
    [ -z "$label" ] && label=$(printf '%s' "$WNAME" | sed -E 's/^[^[:alnum:]]+[[:space:]]*//')
    sub="$SESSION"
    [ -n "$label" ] && sub="$SESSION · $label"
    terminal-notifier \
        -title 'Claude Code' \
        -subtitle "$sub" \
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

dlog "event fired (session=$SESSION wname=[$WNAME])"

case "$EVENT" in
    working)
        autoname_protect
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
        autoname_capture
        window_status '✓'
        alert_tmux
        ;;
    *)
        echo "notify-tmux.sh: unknown event '$EVENT'" >&2
        ;;
esac

exit 0
