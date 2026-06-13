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

# Derive the WINDOW-level @claude_state from every pane's per-pane @claude_state.
# Multiple Claude panes can share one window, so state lives per-pane (set with
# -p below) and the window color is the aggregate. Most-urgent state wins
# (permission > working > question > idle > done) so a finished pane never masks a sibling
# that's still busy or needs you. Panes no longer running Claude are pruned
# (self-heal for crashes/kills that skip SessionEnd); when none remain the window
# option is unset and the tab reverts to its standard colors. The status bar and
# the tmux-windows tv channel read this window option unchanged.
recompute_window_state() {
    [ -n "$WIN_ID" ] || return 0
    local best="" rank=0 pid cmd st r
    while IFS=' ' read -r pid cmd st; do
        [ -n "$st" ] || continue
        case "$cmd" in
            claude|node) : ;;
            *) tmux set-option -pu -t "$pid" @claude_state 2>/dev/null; continue ;;
        esac
        case "$st" in
            permission) r=5 ;;
            working)    r=4 ;;
            question)   r=3 ;;
            idle)       r=2 ;;
            done)       r=1 ;;
            *)          r=0 ;;
        esac
        [ "$r" -gt "$rank" ] && { rank=$r; best=$st; }
    done < <(tmux list-panes -t "$WIN_ID" -F '#{pane_id} #{pane_current_command} #{@claude_state}' 2>/dev/null)
    if [ -n "$best" ]; then
        tmux set-option -w -t "$WIN_ID" @claude_state "$best" 2>/dev/null
        dlog "recompute: window state -> $best"
    else
        tmux set-option -wu -t "$WIN_ID" @claude_state 2>/dev/null
        dlog "recompute: no Claude panes -> unset, revert to standard colors"
    fi
}

# Record this PANE's Claude state (working/permission/idle/done), keep the window
# NAME clean, and re-derive the window color. The original name is captured once
# into @claude_base. No-op when not inside tmux.
window_status() {
    [ -n "$WIN_ID" ] || return 0
    local state="$1"
    # Idempotent: PreToolUse fires working on every tool call, so bail if this
    # pane is already in the requested state — nothing to re-render or recompute.
    if [ -n "$PANE" ]; then
        local cur
        cur=$(tmux show-options -pqv -t "$PANE" @claude_state 2>/dev/null)
        [ "$cur" = "$state" ] && return 0
    fi
    local base
    base=$(tmux show-options -wqv -t "$WIN_ID" @claude_base 2>/dev/null)
    if [ -z "$base" ]; then
        # First touch: adopt the current name as the base, stripping any legacy
        # status glyph left by the old name-prefix scheme.
        base=$(printf '%s' "$WNAME" | sed -E 's/^[^[:alnum:]]+[[:space:]]*//; s/[[:space:]]+$//')
        tmux set-option -w -t "$WIN_ID" @claude_base "$base" 2>/dev/null
    fi
    if [ -n "$PANE" ]; then
        tmux set-option -p -t "$PANE" @claude_state "$state" 2>/dev/null
        recompute_window_state
    else
        # No pane id (rare: hook ran outside a real pane) — set window directly.
        tmux set-option -w -t "$WIN_ID" @claude_state "$state" 2>/dev/null
    fi
    [ -n "$base" ] && tmux rename-window -t "$WIN_ID" "$base" 2>/dev/null || true
}

# Claude exited in this pane: drop its per-pane state and re-derive the window
# color, which reverts to standard if this was the last Claude pane.
clear_pane_state() {
    [ -n "$PANE" ] && tmux set-option -pu -t "$PANE" @claude_state 2>/dev/null
    recompute_window_state
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
    printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null || echo ""
}

# True when Claude ended the turn by asking the user something. The Stop hook's
# stdin carries transcript_path; we read the last assistant text block and test
# whether it ends in '?' (after stripping trailing whitespace and markdown
# punctuation). Used to colour the tab "question" (your move) vs "done" (truly
# finished), since a turn that ends with a question isn't really done.
ends_with_question() {
    local tp last
    tp=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    [ -n "$tp" ] && [ -f "$tp" ] || return 1
    last=$(tail -n 50 "$tp" 2>/dev/null \
        | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null \
        | tail -n 1)
    last=$(printf '%s' "$last" | sed -E 's/[[:space:]*_`")'"'"']+$//')
    case "$last" in *'?') return 0 ;; *) return 1 ;; esac
}

# Read the hook payload once — stdin can only be consumed a single time, and both
# read_message and ends_with_question need fields from it.
INPUT=$(cat 2>/dev/null || true)

dlog "event fired (session=$SESSION wname=[$WNAME])"

case "$EVENT" in
    working)
        autoname_protect
        window_status working
        ;;
    permission_prompt)
        MSG=$(read_message)
        notify "${MSG:-Permission requested}"
        window_status permission
        ;;
    idle_prompt)
        MSG=$(read_message)
        notify "${MSG:-Claude is idle}"
        window_status idle
        alert_tmux
        ;;
    stop)
        notify 'Claude finished'
        autoname_capture
        if ends_with_question; then
            dlog "stop: turn ended with a question -> question state"
            window_status question
        else
            window_status done
        fi
        alert_tmux
        ;;
    exit)
        clear_pane_state
        ;;
    *)
        echo "notify-tmux.sh: unknown event '$EVENT'" >&2
        ;;
esac

exit 0
