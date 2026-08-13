#!/usr/bin/env bash
# Integration tests for zen mode. These run against a tmux server on its own
# socket, so they cannot touch your real session.
#
# The tests replace two functions. "tmux" becomes a shell function that adds the
# test socket, and the script picks it up because it calls tmux through tm().
# zen_font becomes a stub, because the real one would change the font size of
# the Ghostty window that you are looking at now.
set -u
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/executable_tmux-zen.sh"
SOCK="zen-test-$$"
fail=0
check() { # label expected actual
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"
  else printf 'FAIL - %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}

# kill-server does not remove the socket file, so remove it here. If you do not,
# every run leaves a dead socket in the tmux directory.
cleanup() {
  command tmux -L "$SOCK" kill-server 2>/dev/null
  rm -f "${TMUX_TMPDIR:-/private/tmp}/tmux-$(id -u)/$SOCK" "/tmp/tmux-$(id -u)/$SOCK" 2>/dev/null
}
trap cleanup EXIT

source "$SCRIPT" 2>/dev/null

# Send every tmux call from the script to the test socket.
tmux() { command tmux -L "$SOCK" "$@"; }
FONT_LOG=""
zen_font() { FONT_LOG="$FONT_LOG $1"; return 0; }
# The stub font never changes the width, so the real wait would burn its whole
# timeout on every test.
zen_wait_resize() { return 0; }

q() { command tmux -L "$SOCK" display-message -p -t "$1" "$2" 2>/dev/null; }

# --- one pane: enter, then leave ----------------------------------------
command tmux -L "$SOCK" new-session -d -s solo -x 200 -y 50
PANE=$(q solo: '#{pane_id}')

zen_apply_layout "$PANE"
check "3 panes after the split"   "3"     "$(q solo: '#{window_panes}')"
check "2 panes are tagged"        "2"     "$(command tmux -L "$SOCK" list-panes -t solo: -F '#{@zen_pane}' | grep -c 1)"
check "the middle pane is 130 wide" "130"  "$(q "$PANE" '#{pane_width}')"
check "the middle pane has focus"  "$PANE" "$(q solo: '#{pane_id}')"
check "the backdrop is set"        "bg=#000d14" "$(command tmux -L "$SOCK" show -wqv -t solo: window-style)"
check "pane borders are off"       "off"   "$(command tmux -L "$SOCK" show -wqv -t solo: pane-border-status)"
check "the window is marked"       "$PANE" "$(command tmux -L "$SOCK" show -wqv -t solo: @zen_active)"
check "the status bar is hidden"   "off"   "$(command tmux -L "$SOCK" show -qv -t solo status)"

# The gutters must be even, or the middle pane is not in the middle.
LEFT=$(command tmux -L "$SOCK" list-panes -t solo: -F '#{pane_left} #{pane_width} #{@zen_pane}' | awk '$3=="1"' | sort -n | head -1 | cut -d' ' -f2)
RIGHT=$(command tmux -L "$SOCK" list-panes -t solo: -F '#{pane_left} #{pane_width} #{@zen_pane}' | awk '$3=="1"' | sort -n | tail -1 | cut -d' ' -f2)
check "both gutters are the same width" "$LEFT" "$RIGHT"

# sync must hide the status bar for a zen window and show it for another.
command tmux -L "$SOCK" new-window -d -t solo:
ZWIN=$(q "$PANE" '#{window_id}')
OTHER=$(command tmux -L "$SOCK" list-windows -t solo -F '#{window_id}' | grep -v "^$ZWIN$" | head -1)
zen_sync_status "$OTHER"
check "sync shows the bar for an ordinary window" "" "$(command tmux -L "$SOCK" show -qv -t solo status)"
zen_sync_status "$ZWIN"
check "sync hides the bar for a zen window"    "off" "$(command tmux -L "$SOCK" show -qv -t solo status)"

zen_clear_layout "$PANE"
check "back to 1 pane"            "1"  "$(q "$PANE" '#{window_panes}')"
check "the backdrop is dropped"   ""   "$(command tmux -L "$SOCK" show -wqv -t "$ZWIN" window-style)"
check "pane borders come back"    ""   "$(command tmux -L "$SOCK" show -wqv -t "$ZWIN" pane-border-status)"
check "the mark is dropped"       ""   "$(command tmux -L "$SOCK" show -wqv -t "$ZWIN" @zen_active)"
check "the status bar comes back" ""   "$(command tmux -L "$SOCK" show -qv -t solo status)"

# --- more than one pane: the temporary session --------------------------
command tmux -L "$SOCK" new-session -d -s multi -x 200 -y 50
command tmux -L "$SOCK" split-window -h -t multi:
command tmux -L "$SOCK" split-window -v -t multi:
MPANE=$(q multi: '#{pane_id}')
MWIN=$(q multi: '#{window_id}')
MLAYOUT=$(q multi: '#{window_layout}')
check "the window starts with 3 panes" "3" "$(q multi: '#{window_panes}')"

zen_enter_session "$MPANE"
ZSESS=$(zen_session_name multi 0)
command tmux -L "$SOCK" has-session -t "=$ZSESS" 2>/dev/null
check "the temporary session exists" "0" "$?"
check "the original window loses the pane" "2" "$(q "$MWIN" '#{window_panes}')"
check "the pane moved to the zen session"  "$ZSESS" "$(q "$MPANE" '#{session_name}')"
check "the zen window has gutters"         "3" "$(q "$MPANE" '#{window_panes}')"
check "the origin window is recorded"      "$MWIN" "$(command tmux -L "$SOCK" show -qv -t "$ZSESS" @zen_origin_window)"
check "the origin layout is recorded"      "$MLAYOUT" "$(command tmux -L "$SOCK" show -qv -t "$ZSESS" @zen_origin_layout)"
check "the original status bar is untouched" "" "$(command tmux -L "$SOCK" show -qv -t multi status)"

zen_exit_session "$MPANE" "$ZSESS"
check "the pane is home"                   "multi" "$(q "$MPANE" '#{session_name}')"
check "the original window has 3 panes"    "3" "$(q "$MWIN" '#{window_panes}')"
check "the layout is restored exactly"     "$MLAYOUT" "$(q "$MWIN" '#{window_layout}')"
command tmux -L "$SOCK" has-session -t "=$ZSESS" 2>/dev/null
check "the temporary session is gone"      "1" "$?"

# --- a terminal that is not Ghostty gets a plain zoom -------------------
command tmux -L "$SOCK" new-session -d -s plain -x 200 -y 50
command tmux -L "$SOCK" split-window -h -t plain:
PPANE=$(q plain: '#{pane_id}')
zen_toggle "$PPANE" "screen-256color" 2
check "a plain terminal zooms"        "1" "$(q plain: '#{window_zoomed_flag}')"
check "a plain terminal adds no panes" "2" "$(q plain: '#{window_panes}')"
check "a plain terminal skips the font" "" "$FONT_LOG"

# --- the toggle goes both ways ------------------------------------------
FONT_LOG=""
zen_toggle "$PANE" "xterm-ghostty" 1
check "the toggle enters zen mode"  "3" "$(q "$PANE" '#{window_panes}')"
check "the toggle sets the font up" " up" "$FONT_LOG"
zen_toggle "$PANE" "xterm-ghostty" 3
check "the toggle leaves zen mode"  "1" "$(q "$PANE" '#{window_panes}')"
check "the toggle resets the font"  " up reset" "$FONT_LOG"

# --- zen_clean: the font override must not outlive zen mode --------------
# A tmux server that stops during zen mode leaves the font file on disk. Only
# clear it when no window is in zen mode. Kill the other test sessions first,
# because zen_clean looks at every window on the server.
command tmux -L "$SOCK" kill-session -t solo 2>/dev/null
command tmux -L "$SOCK" kill-session -t multi 2>/dev/null
command tmux -L "$SOCK" kill-session -t plain 2>/dev/null
command tmux -L "$SOCK" new-session -d -s clean1 -x 200 -y 50
FONT_LOG=""
zen_clean
check "no zen window -> clears the override" " reset" "$FONT_LOG"

CPANE=$(q clean1: '#{pane_id}')
command tmux -L "$SOCK" set -w -t clean1: @zen_active "$CPANE"
FONT_LOG=""
zen_clean
check "a live zen window -> keeps the override" "" "$FONT_LOG"


# --- the lock stops two toggles from stacking gutters --------------------
# The binding uses "run-shell -b", so two quick presses run two copies of the
# script together. Without the lock both copies build a pair of gutters and the
# window ends up with 5 panes.
ZEN_LOCK="$(mktemp -d)/lock"
command tmux -L "$SOCK" new-session -d -s race -x 200 -y 50
RPANE=$(q race: '#{pane_id}')

zen_lock; check "the first copy takes the lock" "0" "$?"
zen_lock; check "the second copy is refused"    "1" "$?"
zen_unlock
zen_lock; check "the lock frees up again"       "0" "$?"
zen_unlock

# Two toggles racing: run them as background jobs and wait.
zen_toggle "$RPANE" "xterm-ghostty" 1 &
zen_toggle "$RPANE" "xterm-ghostty" 1 &
wait
check "racing toggles still give 3 panes" "3" "$(q race: '#{window_panes}')"
check "racing toggles tag only 2 gutters" "2" "$(command tmux -L "$SOCK" list-panes -t race: -F '#{@zen_pane}' | grep -c 1)"

exit "$fail"
