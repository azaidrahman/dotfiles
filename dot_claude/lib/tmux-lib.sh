# tmux-lib.sh — shared tmux helpers for the hooks and the skill scripts.
# Source this file; do not run it.
#
# Source it with a path relative to the caller's own physical directory, so the
# same line works in the chezmoi source tree, in the applied ~/.claude tree, and
# through the ~/.agents symlinks:
#
#   . "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/tmux-lib.sh"     # hooks
#   . "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/tmux-lib.sh"  # skills
#
# The exit code stays with the caller because severity differs by caller type:
# a hook must exit 0 (silent no-op outside tmux), a skill script must fail loudly
# with its own documented code.

# tmux_require CODE [MSG] — if not inside tmux, print MSG to stderr and exit CODE.
tmux_require() {
    [ -n "${TMUX:-}" ] && return 0
    [ -n "${2:-}" ] && echo "$2" >&2
    exit "$1"
}

# tmux_require_pane CODE [MSG] — like tmux_require, for $TMUX_PANE. Sets PANE on
# success, so callers and tq agree on the target pane.
tmux_require_pane() {
    PANE="${TMUX_PANE:-}"
    [ -n "$PANE" ] && return 0
    [ -n "${2:-}" ] && echo "$2" >&2
    exit "$1"
}

# tq FMT — query tmux about *this* process's pane, not the attached client's
# active window. A bare `display-message -p` reports whatever window the user is
# looking at; -t "$TMUX_PANE" always resolves to the pane this script runs in.
# Falls back to the bare query when no pane id is available.
tq() {
    local pane="${PANE:-${TMUX_PANE:-}}"
    if [ -n "$pane" ]; then
        tmux display-message -p -t "$pane" "$1" 2>/dev/null
    else
        tmux display-message -p "$1" 2>/dev/null
    fi
}
