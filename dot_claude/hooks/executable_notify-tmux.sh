#!/usr/bin/env bash
# Claude Code notification hook — dispatched by event name ($1).
# Wired from ~/.claude/settings.json Notification/Stop/UserPromptSubmit hooks.
set -u

EVENT="${1:-}"
PANE="${TMUX_PANE:-}"

# tq comes from the shared library: it queries *this* Claude pane's window, not
# the attached client's active window.
HOOK_LIB="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib"
. "$HOOK_LIB/tmux-lib.sh"

# The phone sink is optional. chezmoi could apply this hook before the library, so a
# missing module degrades to a no-op instead of breaking every notification.
if [ -f "$HOOK_LIB/push-telegram.sh" ]; then
    . "$HOOK_LIB/push-telegram.sh"
else
    push_telegram() { :; }
fi

SESSION=$(tq '#{session_name}'); SESSION=${SESSION:-unknown}
WINDOW=$(tq '#{window_index}'); WINDOW=${WINDOW:-0}
WIN_ID=$(tq '#{window_id}')
WNAME=$(tq '#{window_name}'); WNAME=${WNAME:-claude}
LOGO="$HOME/.claude/claude-logo.png"
LOG_ALERT="$HOME/.tmux/scripts/log-alert.sh"
FOCUS_DB="$HOME/Library/DoNotDisturb/DB/Assertions.json"

# Seconds the finished turn ran, set once by the stop handler. Empty when unknown.
TURN_ELAPSED=""

# Focus modes in which an audible cue is unwelcome regardless of how blocked the
# session is. Everything else (Work, Personal, Do Not Disturb, Reduce Interruptions)
# still gets the attention sound — the point is to reach you while you're working,
# not while you're asleep. Override with a space-separated list of mode identifiers;
# `tmux` is irrelevant here, these are macOS Focus identifiers from ModeConfigurations.
SILENT_MODES="${CLAUDE_NOTIFY_SILENT_MODES:-com.apple.sleep.sleep-mode com.apple.donotdisturb.mode.paintpalettefill}"

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
    while IFS=' ' read -r pid cmd; do
        # Read the pane option directly. The #{@claude_state} format falls back
        # to the WINDOW option when the pane option is unset, so a just-cleared
        # pane would echo the window's own stale value back and the state would
        # never clear.
        st=$(tmux show-options -pqv -t "$pid" @claude_state 2>/dev/null)
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
    done < <(tmux list-panes -t "$WIN_ID" -F '#{pane_id} #{pane_current_command}' 2>/dev/null)
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
    else
        # Honor a manual rename. We re-render the window to @claude_base on every
        # state change, so a user `rename-window` would otherwise be reverted on
        # the next event. If the live name (minus our status glyph) diverged from
        # @claude_base, the user renamed it themselves — adopt their name as the
        # new base and claim autoname_done so stop-capture won't fight it either.
        local live
        live=$(printf '%s' "$WNAME" | sed -E 's/^[^[:alnum:]]+[[:space:]]*//; s/[[:space:]]+$//')
        if [ -n "$live" ] && [ "$live" != "$base" ] && ! is_default_name "$live"; then
            dlog "manual rename: live=[$live] != base=[$base] -> adopt"
            base="$live"
            tmux set-option -w -t "$WIN_ID" @claude_base "$base" 2>/dev/null
            tmux set-option -w -t "$WIN_ID" @claude_autoname_done 1 2>/dev/null
        fi
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

# notify <tier> <message> — tier is `attn` (Claude needs you) or `done` (turn
# finished). The tier decides three things:
#
#   sound  — both tiers chime, but with deliberately dissimilar samples so the two
#            are tellable apart without looking at the screen: a fanfare means come
#            here, a short click means it's just finished. Overridable per tier via
#            $CLAUDE_NOTIFY_SOUND / $CLAUDE_NOTIFY_SOUND_DONE.
#   group  — notification group keys are per-tier, not per-session. terminal-notifier
#            REPLACES an existing notification sharing a group, so a single
#            "claude-$SESSION" key meant a permission prompt followed by a stop left
#            only the stop on screen — the one asking for input silently vanished.
#   title  — says which tier up front, so it reads without parsing the subtitle.
#   Focus  — who plays the sound decides whether Focus can suppress it. `attn` plays
#            its own via play_sound/afplay, which Focus does not gate, so a blocked
#            session still reaches you while Work/Personal/DND is on. `done` passes
#            -sound to terminal-notifier and is therefore governed by macOS, so Focus
#            silences it — intended, not a defect. Do NOT "fix" that by moving `done`
#            onto play_sound. Note -ignoreDnD is absent from both tiers on purpose:
#            it is a dead pre-Focus private API on macOS 12+ and does nothing.
# Identifier of the currently active macOS Focus mode, empty when Focus is off.
active_focus_mode() {
    [ -f "$FOCUS_DB" ] || return 0
    jq -r '.data[0].storeAssertionRecords[]?.assertionDetails.assertionDetailsModeIdentifier // empty' \
        "$FOCUS_DB" 2>/dev/null | head -n 1
}

# Seconds since the last keyboard or mouse input, empty if the probe fails. IOKit
# reports this in nanoseconds. $CLAUDE_PUSH_IOREG exists so the tests can point the
# probe at a path that does not exist.
hid_idle_secs() {
    "${CLAUDE_PUSH_IOREG:-ioreg}" -c IOHIDSystem 2>/dev/null \
        | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }'
}

# True when the screen is locked. The key is absent while unlocked, and some macOS
# versions report it as false instead, so test the value rather than the key.
screen_locked() {
    "${CLAUDE_PUSH_IOREG:-ioreg}" -n Root -d1 -a 2>/dev/null \
        | grep -A1 'CGSSessionScreenIsLocked' \
        | grep -q '<true/>'
}

# True when you are away from this Mac, which is the only time the phone should ring.
# While you are at the keyboard the Mac notification already has your attention, and
# a second buzz in your pocket is pure noise — which is how a topic ends up muted.
#
# A lock counts as away on its own. If you lock the screen and walk off, idle time is
# still near zero for the next few minutes, and that is exactly the window where the
# push matters most.
#
# If the probe fails we report present, so nothing is pushed. That is deliberate: a
# missed push costs you less than a phone buzzing on the desk, and the local
# notification has already fired either way.
user_is_away() {
    [ -n "${CLAUDE_PUSH_ALWAYS:-}" ] && return 0
    screen_locked && return 0
    local idle threshold
    threshold="${CLAUDE_PUSH_IDLE_SECS:-300}"
    idle=$(hid_idle_secs)
    [ -n "$idle" ] || { dlog "away-gate: no idle reading -> assume present"; return 1; }
    [ "$idle" -ge "$threshold" ]
}

# Where this turn's start time is recorded. One file for each Claude session, so
# concurrent sessions keep separate clocks. session_id comes from the hook payload;
# the pane id and the parent pid are fallbacks for when it is absent.
turn_clock_file() {
    local key
    key=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    [ -n "$key" ] || key="${PANE:-$PPID}"
    key=$(printf '%s' "$key" | tr -c 'A-Za-z0-9_-' '_')
    mkdir -p "$HOME/.claude/turn" 2>/dev/null
    printf '%s/.claude/turn/%s' "$HOME" "$key"
}

# Start the clock for this turn. Runs on `working`, which fires both when you send a
# prompt and on every tool call. Only the first one records a time, so a long turn
# full of tool calls does not keep looking brand new.
turn_start() {
    local f; f=$(turn_clock_file)
    [ -f "$f" ] && return 0
    date +%s > "$f" 2>/dev/null
    dlog "turn: clock started"
}

# Drop this session's clock, and age out any that were orphaned. A crash skips
# SessionEnd, so those clocks are never cleared by their own session — the next
# clean exit removes anything left from a previous day. Pruning here rather than in
# turn_start matters: turn_start runs on every tool call, and a find on that path
# would be paid thousands of times a day.
turn_clear() {
    rm -f "$(turn_clock_file)" 2>/dev/null
    find "$HOME/.claude/turn" -type f -mtime +1 -delete 2>/dev/null
    dlog "turn: clock cleared, stale clocks pruned"
}

# Seconds this turn has run, empty when no clock exists. Clears the clock.
turn_elapsed() {
    local f start; f=$(turn_clock_file)
    [ -f "$f" ] || return 0
    start=$(cat "$f" 2>/dev/null)
    rm -f "$f" 2>/dev/null
    case "$start" in ''|*[!0-9]*) return 0 ;; esac
    printf '%s' "$(( $(date +%s) - start ))"
}

# Should a FINISHED turn reach the phone? Only when it ran long enough that you
# stopped watching it. A turn that took three seconds finished while you were
# reading it, and a message about it is noise — at roughly 40 turns a day, that
# noise is what buries the messages that matter.
#
# This gates `done` only. A blocked session always reaches you, however quick it
# was, because being quick is no reason to leave you stuck.
#
# With no clock at all — the hook was added mid-turn, or the file was cleared — push
# rather than swallow it. Failing toward a message is the safer direction here,
# unlike the away-gate, where a false push is the annoying outcome.
# Reads $TURN_ELAPSED rather than calling turn_elapsed itself. The stop handler
# clears the clock exactly once, before it decides anything, so a turn that is not
# pushed still ends its clock. Otherwise a suppressed turn would leave its start
# time behind and make the NEXT turn look long enough to push.
done_is_worth_pushing() {
    local elapsed threshold
    threshold="${CLAUDE_PUSH_DONE_MIN_SECS:-60}"
    elapsed="$TURN_ELAPSED"
    if [ -z "$elapsed" ]; then
        dlog "turn: no clock -> push anyway"
        return 0
    fi
    dlog "turn: ran ${elapsed}s, threshold ${threshold}s"
    [ "$elapsed" -ge "$threshold" ]
}

# Play an alert sound ourselves instead of asking terminal-notifier to do it.
#
# This exists because a Focus mode suppresses notification *presentation* — banner and
# sound both — while still filing the notification into Notification Center. On
# macOS 15 every Focus mode here is an allow-list containing zero apps, so nothing
# gets through. terminal-notifier's -ignoreDnD cannot help: it sets a private
# NSUserNotification flag from the pre-Focus DND era that macOS 12+ ignores outright,
# and real breakthrough needs Time Sensitive / Critical Alert entitlements only Apple
# grants to signed apps.
#
# afplay is not a notification, just audio playback, so Focus does not gate it. That
# makes it the only entitlement-free way an attention cue survives Focus. Backgrounded
# and fully detached so the hook never blocks on ~1s of audio.
play_sound() {
    local name="$1" f="/System/Library/Sounds/$1.aiff" mode m
    [ -f "$f" ] || { dlog "play_sound: no such sound [$name]"; return 0; }
    command -v afplay >/dev/null || return 0
    mode=$(active_focus_mode)
    if [ -n "$mode" ]; then
        for m in $SILENT_MODES; do
            [ "$mode" = "$m" ] && { dlog "play_sound: [$name] suppressed by focus mode $mode"; return 0; }
        done
        dlog "play_sound: [$name] through focus mode $mode"
    fi
    ( afplay "$f" >/dev/null 2>&1 & ) >/dev/null 2>&1
}

notify() {
    local tier="$1" msg="$2"
    # Subtitle = session + the window's topic, so concurrent sessions are easy to
    # tell apart. Prefer @claude_base (the clean auto-named topic, no status glyph);
    # fall back to the window name with any leading glyph/spaces stripped.
    local label sub
    label=$(tmux show-options -wqv -t "$WIN_ID" @claude_base 2>/dev/null)
    [ -z "$label" ] && label=$(printf '%s' "$WNAME" | sed -E 's/^[^[:alnum:]]+[[:space:]]*//')
    sub="$SESSION"
    [ -n "$label" ] && sub="$SESSION · $label"

    local title sound via_afplay
    case "$tier" in
        # Hero is the loudest sound macOS ships (peak -5.4 dB / RMS -24.4 dB, 1.06s),
        # which matters because alert volume is already maxed — quieter samples like
        # Sosumi (-13.7/-33.2) cannot be turned up any further.
        attn) title='Claude Code · needs you'; sound="${CLAUDE_NOTIFY_SOUND:-Hero}";      via_afplay=1 ;;
        # Tink for `done`: a 0.56s click, the shortest sound available and tonally
        # nothing like Hero's fanfare, so the tiers stay distinguishable by ear. Still
        # audible (peak -8.8 dB) rather than one of the near-inaudible ones.
        *)    title='Claude Code';             sound="${CLAUDE_NOTIFY_SOUND_DONE:-Tink}"; via_afplay='' ;;
    esac

    # The phone, but only when you are not here to see the Mac. This runs BEFORE the
    # terminal-notifier guard below on purpose: the two sinks are independent, and a
    # machine without that cask installed should still be able to reach you.
    # push_telegram detaches its own request, so this cannot block the stop path.
    #
    # The push names the machine; the local notification does not. One Telegram chat
    # collects every machine, so a buzz that does not say `aqua` or `onyx` cannot tell
    # you which one is blocked. On the Mac itself the name is noise — you are looking
    # at it. Set $CLAUDE_PUSH_HOST to override the label.
    if user_is_away; then
        local host push_sub
        host="${CLAUDE_PUSH_HOST:-$(hostname -s 2>/dev/null)}"
        push_sub="$sub"
        [ -n "$host" ] && push_sub="$host · $sub"
        if [ "$tier" = "attn" ] || done_is_worth_pushing; then
            dlog "push: away -> phone, tier=$tier host=$host"
            push_telegram "$tier" "$title" "$push_sub" "$msg"
        else
            dlog "push: done but the turn was short, skipping"
        fi
    else
        dlog "push: present -> Mac only, tier=$tier"
    fi

    # The Mac banner and its cue are optional. Once the phone rings for everything,
    # they are a second alert for the same event. CLAUDE_NOTIFY_LOCAL=0 drops both.
    # The tmux tab colour and the window name still change, and those are the ambient
    # signal at the desk — this only removes the interruption.
    if [ "${CLAUDE_NOTIFY_LOCAL:-1}" = "0" ]; then
        dlog "local: suppressed by CLAUDE_NOTIFY_LOCAL=0"
        return 0
    fi

    command -v terminal-notifier >/dev/null || return 0

    set -- \
        -title "$title" \
        -subtitle "$sub" \
        -message "$msg" \
        -contentImage "$LOGO" \
        -group "claude-$SESSION-$tier"

    if [ -n "$via_afplay" ]; then
        # attn: play the cue ourselves so Focus cannot swallow it, and leave -sound off
        # the notification so a Focus-free moment does not chime twice.
        play_sound "$sound"
    else
        # done: hand the sound to macOS, which is precisely what makes Focus suppress
        # it. A finished turn has no right to interrupt; only a blocked one does.
        set -- "$@" -sound "$sound"
    fi
    terminal-notifier "$@" >/dev/null 2>&1 || true
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
        turn_start
        window_status working
        ;;
    permission_prompt)
        MSG=$(read_message)
        notify attn "${MSG:-Permission requested}"
        window_status permission
        ;;
    idle_prompt)
        MSG=$(read_message)
        notify attn "${MSG:-Claude is idle}"
        window_status idle
        alert_tmux
        ;;
    stop)
        # autoname_capture first: it sets @claude_base, which notify reads for the
        # subtitle. Notifying before capture left the very first notification of a
        # session with no topic label.
        autoname_capture
        TURN_ELAPSED=$(turn_elapsed)
        if ends_with_question; then
            dlog "stop: turn ended with a question -> question state"
            notify attn 'Claude asked you a question'
            window_status question
        else
            notify done 'Claude finished'
            window_status done
        fi
        alert_tmux
        ;;
    exit)
        clear_pane_state
        turn_clear
        ;;
    *)
        echo "notify-tmux.sh: unknown event '$EVENT'" >&2
        ;;
esac

exit 0
