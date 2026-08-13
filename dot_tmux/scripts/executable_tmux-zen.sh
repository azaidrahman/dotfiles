#!/usr/bin/env bash
# Zen mode for tmux, in the style of zen-mode.nvim.
#
# If the client is Ghostty, prefix+z does three things at the same time:
#   1. It sets the Ghostty font size to 24.
#   2. It puts the pane in the middle of two empty gutter panes.
#   3. It makes the gutters dark and hides the status bar.
# If the client is not Ghostty, prefix+z does a plain zoom. prefix+Z always
# does a plain zoom.
#
# Ghostty has no remote control socket, so a script cannot set the font size
# directly. The font size comes from two Ghostty keybinds that this script
# sends with osascript: cmd+ctrl+shift+z (size 24) and cmd+ctrl+shift+x
# (reset). Both chords are hard to press by accident, which is why they were
# chosen.
#
# reload-config.scpt sends its chord with "keystroke". Do not copy that here.
# "keystroke" sends a character, and a control and a letter together become one
# control character, so Ghostty sees no z key and matches no keybind. Use
# "key code" instead. See zen_font below.
#
# A Ghostty keybind cannot do the toggle on its own. set_font_size takes an
# absolute size, and Ghostty runs the keybind before tmux runs this script, so
# Ghostty cannot know if you want to enter zen mode or leave it. The script
# holds the state, so the script must send the chord.
#
# If the window holds more than one pane, gutters are not possible. The script
# then moves the pane into a temporary session and applies zen mode there. The
# original window keeps its layout. To leave zen mode, the script moves the
# pane home, restores the saved layout, and kills the temporary session.
#
# Usage:
#   tmux-zen.sh <pane_id> <client_termname> <window_panes>   Toggle zen mode.
#   tmux-zen.sh sync <window_id>                             Hook. See below.
#
# The status bar is a session option, not a window option. tmux cannot hide it
# for one window only. The sync command runs from the after-select-window hook.
# It hides the status bar if the new window is a zen window, and shows it again
# if the new window is not. Without the hook, every other window in the session
# would lose its status bar while zen mode is on.

ZEN_DEFAULT_PCT=55        # Width of the middle pane, as a percent of the window.
ZEN_MIN_CENTER=40         # Never make the middle pane thinner than this.
ZEN_MIN_GUTTER=6          # If a gutter is thinner than this, skip the gutters.
ZEN_BACKDROP='bg=#000d14' # One step darker than the global window-style.
ZEN_RESIZE_TIMEOUT_MS=800 # How long to wait for tmux to see the new font size.

zen_tmux() { tmux "$@" 2>/dev/null; }

# --- pure helpers (the tests cover these) --------------------------------

# Report if the client runs Ghostty. tmux sets TERM_PROGRAM to "tmux" inside a
# pane, so that variable is useless here. The client termname is reliable, and
# Ghostty reports xterm-ghostty.
zen_is_ghostty() {
  case "${1:-}" in
    *ghostty*) return 0 ;;
    *) return 1 ;;
  esac
}

# Read the @zen-width option and give back a percent. If the value is bad or
# out of range, give back the default.
zen_pct() {
  local raw=${1:-}
  raw=${raw%\%}
  case "$raw" in
    '' | *[!0-9]*) printf '%s\n' "$ZEN_DEFAULT_PCT"; return ;;
  esac
  if [ "$raw" -lt 20 ] || [ "$raw" -gt 95 ]; then
    printf '%s\n' "$ZEN_DEFAULT_PCT"
  else
    printf '%s\n' "$raw"
  fi
}

# Give the width of the middle pane in columns.
zen_center_cols() {
  local width=$1 pct=${2:-$ZEN_DEFAULT_PCT} cols
  cols=$(( width * pct / 100 ))
  [ "$cols" -lt "$ZEN_MIN_CENTER" ] && cols=$ZEN_MIN_CENTER
  [ "$cols" -gt "$width" ] && cols=$width
  printf '%s\n' "$cols"
}

# Give the width of one gutter in columns. Two columns of the window go to the
# two pane borders.
zen_gutter_cols() {
  local width=$1 center=$2 cols
  cols=$(( (width - center - 2) / 2 ))
  [ "$cols" -lt 0 ] && cols=0
  printf '%s\n' "$cols"
}

# Report if the gutters are wide enough to be worth the trouble.
zen_gutters_fit() {
  case "${1:-}" in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge "$ZEN_MIN_GUTTER" ]
}

# Build the name of the temporary session. A tmux session name cannot hold a
# "." or a ":", so replace every character that is not safe.
zen_session_name() {
  local safe=${1//[^A-Za-z0-9_-]/-}
  printf 'zen-%s-%s\n' "$safe" "${2:-0}"
}

# --- Ghostty font size ---------------------------------------------------

# Send one of the two Ghostty font keybinds. If Ghostty is not on this machine,
# do nothing and report success: the rest of zen mode still works. This matters
# when you attach over SSH from Ghostty on another machine, because the client
# termname is xterm-ghostty but the app is somewhere else.
# Send the key as a key code, not as a character. "keystroke" sends a
# character, and "control down" turns a control and a letter into one control
# character. Ghostty then never sees a z key, so it matches no keybind. A key
# code sends the physical key with the modifier flags, which is what Ghostty
# matches. Key code 6 is z. Key code 7 is x. These are the codes for a US
# layout, which is the layout on this machine.
zen_font() {
  local code
  [ "$(uname)" = "Darwin" ] || return 0
  [ -d /Applications/Ghostty.app ] || return 0
  case "${1:-}" in
    up)    code=6 ;;
    reset) code=7 ;;
    *) return 0 ;;
  esac
  osascript >/dev/null 2>&1 <<EOF
tell application "Ghostty" to activate
tell application "System Events" to key code $code using {command down, control down, shift down}
EOF
  return 0
}

# A new font size gives the window a new number of columns. Wait for tmux to
# see the change, because the gutter arithmetic needs the new width. If the
# width does not change, give up and use the width that is there.
zen_wait_resize() {
  local pane=$1 before=$2 waited=0 now
  while [ "$waited" -lt "$ZEN_RESIZE_TIMEOUT_MS" ]; do
    now=$(zen_tmux display-message -p -t "$pane" '#{window_width}')
    if [ -n "$now" ] && [ "$now" != "$before" ]; then
      return 0
    fi
    sleep 0.05
    waited=$(( waited + 50 ))
  done
  return 1
}

# --- layout --------------------------------------------------------------

# Put the pane in the middle of two empty gutter panes, then dress the window.
# The gutters run "cat" to hold the pane open. Each gutter carries a @zen_pane
# option, so the teardown can find them. Do not look for the "cat" process to
# find them: any ordinary window could hold a pane that runs cat.
zen_apply_layout() {
  local pane=$1 session width center gutter left right
  session=$(zen_tmux display-message -p -t "$pane" '#{session_name}')
  width=$(zen_tmux display-message -p -t "$pane" '#{window_width}')
  center=$(zen_center_cols "$width" "$(zen_pct "$(zen_tmux show -wqv -t "$pane" @zen-width)")")
  gutter=$(zen_gutter_cols "$width" "$center")

  if zen_gutters_fit "$gutter"; then
    left=$(zen_tmux split-window -hbd -P -F '#{pane_id}' -t "$pane" 'cat')
    right=$(zen_tmux split-window -hd -P -F '#{pane_id}' -t "$pane" 'cat')
    zen_tmux select-layout -t "$pane" even-horizontal
    if [ -n "$left" ]; then
      zen_tmux set -p -t "$left" @zen_pane 1
      zen_tmux resize-pane -t "$left" -x "$gutter"
    fi
    if [ -n "$right" ]; then
      zen_tmux set -p -t "$right" @zen_pane 1
      zen_tmux resize-pane -t "$right" -x "$gutter"
    fi
  else
    zen_tmux display-message "zen: window is too narrow for gutters"
  fi

  # tmux has only two pane style slots, active and inactive, so this darkens
  # every inactive pane in the window. The gutters are empty, so it reads as a
  # backdrop. It is not a true per-pane dim.
  zen_tmux set -w -t "$pane" window-style "$ZEN_BACKDROP"
  zen_tmux set -w -t "$pane" pane-border-status off
  zen_tmux set -w -t "$pane" @zen_active "$pane"
  zen_tmux set -t "$session" status off
  zen_tmux select-pane -t "$pane"
}

# Remove the gutters and put the window options back. "set -u" drops the
# window level value, so the global value from visual.conf applies again.
zen_clear_layout() {
  local pane=$1 window session gutter
  window=$(zen_tmux display-message -p -t "$pane" '#{window_id}')
  session=$(zen_tmux display-message -p -t "$pane" '#{session_name}')
  for gutter in $(zen_tmux list-panes -t "$window" -F '#{pane_id} #{@zen_pane}' | awk '$2 == "1" { print $1 }'); do
    zen_tmux kill-pane -t "$gutter"
  done
  zen_tmux set -uw -t "$window" window-style
  zen_tmux set -uw -t "$window" pane-border-status
  zen_tmux set -uw -t "$window" @zen_active
  zen_tmux set -u -t "$session" status
  zen_tmux select-pane -t "$pane"
}

# --- the temporary session (windows with more than one pane) -------------

# Move the pane into a temporary session, then apply zen mode there. Save the
# layout of the original window first. A pane keeps its id when it moves, and a
# tmux layout string holds pane ids, so the saved string restores the original
# layout exactly.
zen_enter_session() {
  local pane=$1 session window index layout path zsession placeholder
  session=$(zen_tmux display-message -p -t "$pane" '#{session_name}')
  window=$(zen_tmux display-message -p -t "$pane" '#{window_id}')
  index=$(zen_tmux display-message -p -t "$pane" '#{window_index}')
  layout=$(zen_tmux display-message -p -t "$pane" '#{window_layout}')
  path=$(zen_tmux display-message -p -t "$pane" '#{pane_current_path}')
  zsession=$(zen_session_name "$session" "$index")

  if zen_tmux has-session -t "=$zsession"; then
    zen_tmux display-message "zen: session $zsession is already there"
    return 1
  fi
  zen_tmux new-session -d -s "$zsession" -c "$path" || return 1

  # new-session makes a placeholder pane. Note it, move the real pane in, then
  # kill the placeholder. This leaves the real pane alone in the window.
  placeholder=$(zen_tmux list-panes -t "$zsession:" -F '#{pane_id}' | head -1)
  if ! zen_tmux join-pane -h -s "$pane" -t "$zsession:"; then
    zen_tmux kill-session -t "=$zsession"
    return 1
  fi
  [ -n "$placeholder" ] && zen_tmux kill-pane -t "$placeholder"

  zen_tmux set -t "$zsession" @zen_owned 1
  zen_tmux set -t "$zsession" @zen_origin_session "$session"
  zen_tmux set -t "$zsession" @zen_origin_window "$window"
  zen_tmux set -t "$zsession" @zen_origin_layout "$layout"

  zen_apply_layout "$pane"
  zen_tmux switch-client -t "$zsession"
}

# Move the pane home, restore the layout of the original window, and kill the
# temporary session. tmux kills a session when its last window closes, so the
# kill-session call is only a safety net.
zen_exit_session() {
  local pane=$1 zsession=$2 osession owindow olayout
  osession=$(zen_tmux show -qv -t "$zsession" @zen_origin_session)
  owindow=$(zen_tmux show -qv -t "$zsession" @zen_origin_window)
  olayout=$(zen_tmux show -qv -t "$zsession" @zen_origin_layout)

  zen_clear_layout "$pane"

  # If the original window is gone, keep the pane where it is. A stranded pane
  # is better than a lost one.
  if ! zen_tmux join-pane -s "$pane" -t "$owindow"; then
    zen_tmux set -u -t "$zsession" @zen_owned
    zen_tmux display-message "zen: the original window is gone, the pane stays in $zsession"
    return 1
  fi
  [ -n "$olayout" ] && zen_tmux select-layout -t "$owindow" "$olayout"
  zen_tmux switch-client -t "$osession"
  zen_tmux select-pane -t "$pane"
  zen_tmux kill-session -t "=$zsession"
  return 0
}

# --- commands ------------------------------------------------------------

zen_toggle() {
  local pane=${1:-} term=${2:-} panes=${3:-1} session before

  [ -n "$pane" ] || return 0
  session=$(zen_tmux display-message -p -t "$pane" '#{session_name}')

  # Leave zen mode. Check the temporary session first, because a pane in one is
  # also inside a zen window.
  if [ "$(zen_tmux show -qv -t "$session" @zen_owned)" = "1" ]; then
    zen_font reset
    zen_exit_session "$pane" "$session"
    return 0
  fi
  if [ -n "$(zen_tmux show -wqv -t "$pane" @zen_active)" ]; then
    zen_font reset
    zen_clear_layout "$pane"
    return 0
  fi

  # Enter zen mode. Any terminal that is not Ghostty gets a plain zoom, so a
  # phone or a Termius session behaves as it did before.
  if ! zen_is_ghostty "$term"; then
    zen_tmux resize-pane -Z -t "$pane"
    return 0
  fi

  # Change the font size first. The gutter arithmetic needs the new width.
  before=$(zen_tmux display-message -p -t "$pane" '#{window_width}')
  zen_font up
  zen_wait_resize "$pane" "$before"

  if [ "${panes:-1}" -gt 1 ]; then
    zen_enter_session "$pane" || zen_font reset
  else
    zen_apply_layout "$pane"
  fi
  return 0
}

# Hide the status bar only while a zen window is on screen. See the note at the
# top of this file.
zen_sync_status() {
  local window=${1:-}
  [ -n "$window" ] || return 0
  if [ -n "$(zen_tmux show -wqv -t "$window" @zen_active)" ]; then
    zen_tmux set status off
  else
    zen_tmux set -u status
  fi
  return 0
}

main() {
  case "${1:-}" in
    sync) zen_sync_status "${2:-}" ;;
    *) zen_toggle "${1:-}" "${2:-}" "${3:-}" ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
