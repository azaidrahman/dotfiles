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
# directly. Ghostty does reload its configuration when it gets SIGUSR2. The main
# Ghostty configuration includes ZEN_FONT_CONF with a "?" prefix, which means
# the file can be absent. This script writes the font size to that file and then
# sends the signal. See zen_font below.
#
# An earlier version sent a Ghostty keybind with osascript. Do not go back to
# that. It cost about 130 ms, it needed Ghostty in front of the other windows,
# and a global hotkey tool such as Alfred or Karabiner can take the chord first.
# A signal costs about 1 ms and no other program can take it.
#
# If the window holds more than one pane, gutters are not possible. The script
# then moves the pane into a temporary session and applies zen mode there. The
# original window keeps its layout. To leave zen mode, the script moves the
# pane home, restores the saved layout, and kills the temporary session.
#
# Usage:
#   tmux-zen.sh <pane_id> <termname> <window_panes> <client>  Toggle zen mode.
#   tmux-zen.sh sync <window_id>                             Hook. See below.
#
# The status bar is a session option, not a window option. tmux cannot hide it
# for one window only. The sync command runs from the after-select-window hook.
# It hides the status bar if the new window is a zen window, and shows it again
# if the new window is not. Without the hook, every other window in the session
# would lose its status bar while zen mode is on.

# Width of the middle pane, as a percent of the window. At font size 24 the
# window is about 158 columns, so 65 percent gives a middle pane of 102 columns
# and gutters of 27 columns. To change it, set the @zen-width option. Use
# "tmux set -g @zen-width 70" for every window, or "tmux set -w @zen-width 70"
# for one window. A window value wins over a global value.
ZEN_DEFAULT_PCT=65
ZEN_MIN_CENTER=40         # Never make the middle pane thinner than this.
ZEN_MIN_GUTTER=6          # If a gutter is thinner than this, skip the gutters.
ZEN_BACKDROP='bg=#000d14' # One step darker than the global window-style.
ZEN_FONT_SIZE=24          # Ghostty font size in zen mode.
ZEN_RESIZE_TIMEOUT_MS=800 # How long to wait for tmux to see the new font size.
ZEN_RESIZE_POLL_MS=20     # How often to look. The real change takes about 100 ms.

# The Ghostty configuration includes this file. Keep it out of ~/.config, because
# chezmoi manages that directory and this file changes at run time.
ZEN_FONT_CONF="${ZEN_FONT_CONF:-$HOME/.cache/ghostty/zen-font.conf}"

zen_tmux() { tmux "$@" 2>/dev/null; }

# --- one toggle at a time ------------------------------------------------

# The key binding uses "run-shell -b", so tmux starts this script in the
# background and returns at once. Two quick presses of prefix+z would then run
# two copies together. Both copies read the state before either copy writes it,
# so both decide to enter zen mode and each one builds its own pair of gutters.
# The window ends up with 5 or 7 panes and a very thin middle pane.
#
# mkdir either makes the directory or fails, and nothing in between, so it works
# as a lock. A copy that cannot take the lock exits and ignores the key press.
ZEN_LOCK="${TMPDIR:-/tmp}/tmux-zen-$(id -u).lock"
ZEN_LOCK_STALE_S=10

zen_lock_age() {
  local mtime
  mtime=$(stat -f %m "$ZEN_LOCK" 2>/dev/null || stat -c %Y "$ZEN_LOCK" 2>/dev/null)
  [ -n "$mtime" ] || return 1
  printf '%s\n' "$(( $(date +%s) - mtime ))"
}

zen_lock() {
  local age
  mkdir "$ZEN_LOCK" 2>/dev/null && return 0
  # A script that was killed leaves the lock behind. Drop an old one.
  age=$(zen_lock_age) || return 1
  [ "$age" -ge "$ZEN_LOCK_STALE_S" ] || return 1
  rmdir "$ZEN_LOCK" 2>/dev/null
  mkdir "$ZEN_LOCK" 2>/dev/null
}

zen_unlock() { rmdir "$ZEN_LOCK" 2>/dev/null; return 0; }

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

# Set the Ghostty font size, or put it back. Write the size to the file that the
# Ghostty configuration includes, then tell Ghostty to reload with SIGUSR2. An
# empty file means Ghostty uses the size from the main configuration.
#
# If Ghostty does not run on this machine, do nothing and report success: the
# rest of zen mode still works. This matters when you attach over SSH from
# Ghostty on another machine. The client termname is xterm-ghostty, but the app
# is somewhere else, so there is no process here to signal.
#
# The reload is global. Every Ghostty window gets the new size, and a font size
# that you set by hand goes back to the size in the configuration.
zen_font() {
  local pid
  [ "$(uname)" = "Darwin" ] || return 0
  pid=$(pgrep -x ghostty 2>/dev/null | head -1)
  [ -n "$pid" ] || return 0
  mkdir -p "$(dirname "$ZEN_FONT_CONF")" 2>/dev/null || return 0
  case "${1:-}" in
    up)    printf 'font-size = %s\n' "$ZEN_FONT_SIZE" > "$ZEN_FONT_CONF" || return 0 ;;
    reset) : > "$ZEN_FONT_CONF" || return 0 ;;
    *) return 0 ;;
  esac
  kill -USR2 "$pid" 2>/dev/null
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
    # printf is a shell builtin, so this starts no extra process. The format
    # turns milliseconds into the seconds that sleep wants, for 1 to 999 ms.
    sleep "$(printf '0.%03d' "$ZEN_RESIZE_POLL_MS")"
    waited=$(( waited + ZEN_RESIZE_POLL_MS ))
  done
  return 1
}

# --- layout --------------------------------------------------------------

# Put the pane in the middle of two empty gutter panes, then dress the window.
# The gutters run "cat" to hold the pane open. Each gutter carries a @zen_pane
# option, so the teardown can find them. Do not look for the "cat" process to
# find them: any ordinary window could hold a pane that runs cat.
# Every call to tmux is a new client, and each one costs about 13 ms. Read all
# the values in one call, and send all the changes in one call. tmux takes many
# commands in one invocation when you separate them with a ";" argument.
zen_apply_layout() {
  local pane=$1 session width pct center gutter left right

  { read -r width; read -r pct; read -r session; } <<< "$(zen_tmux display-message -p -t "$pane" \
    "#{window_width}
#{@zen-width}
#{session_name}")"

  center=$(zen_center_cols "$width" "$(zen_pct "$pct")")
  gutter=$(zen_gutter_cols "$width" "$center")

  # tmux has only two pane style slots, active and inactive, so the backdrop
  # darkens every inactive pane in the window. The gutters are empty, so it
  # reads as a backdrop. It is not a true per-pane dim.
  if zen_gutters_fit "$gutter"; then
    { read -r left; read -r right; } <<< "$(zen_tmux \
      split-window -hbd -P -F '#{pane_id}' -t "$pane" 'cat' ';' \
      split-window -hd -P -F '#{pane_id}' -t "$pane" 'cat')"
    zen_tmux \
      select-layout -t "$pane" even-horizontal ';' \
      set -p -t "$left" @zen_pane 1 ';' \
      set -p -t "$right" @zen_pane 1 ';' \
      resize-pane -t "$left" -x "$gutter" ';' \
      resize-pane -t "$right" -x "$gutter" ';' \
      set -w -t "$pane" window-style "$ZEN_BACKDROP" ';' \
      set -w -t "$pane" pane-border-status off ';' \
      set -w -t "$pane" @zen_active "$pane" ';' \
      set -t "$session" status off ';' \
      select-pane -t "$pane"
  else
    zen_tmux \
      display-message "zen: window is too narrow for gutters" ';' \
      set -w -t "$pane" window-style "$ZEN_BACKDROP" ';' \
      set -w -t "$pane" pane-border-status off ';' \
      set -w -t "$pane" @zen_active "$pane" ';' \
      set -t "$session" status off ';' \
      select-pane -t "$pane"
  fi
}

# Remove the gutters and put the window options back. "set -u" drops the
# window level value, so the global value from visual.conf applies again.
zen_clear_layout() {
  local pane=$1 window session gutter kills=()

  { read -r window; read -r session; } <<< "$(zen_tmux display-message -p -t "$pane" \
    "#{window_id}
#{session_name}")"

  for gutter in $(zen_tmux list-panes -t "$window" -F '#{pane_id} #{@zen_pane}' | awk '$2 == "1" { print $1 }'); do
    kills+=(kill-pane -t "$gutter" ';')
  done

  # Expand the array the safe way. A plain "${kills[@]}" on an empty array is an
  # error under "set -u" in bash 3.2, which is the bash that macOS ships.
  zen_tmux ${kills[@]+"${kills[@]}"} \
    set -uw -t "$window" window-style ';' \
    set -uw -t "$window" pane-border-status ';' \
    set -uw -t "$window" @zen_active ';' \
    set -u -t "$session" status ';' \
    select-pane -t "$pane"
}

# --- the temporary session (windows with more than one pane) -------------

# Move the pane into a temporary session, then apply zen mode there. Save the
# layout of the original window first. A pane keeps its id when it moves, and a
# tmux layout string holds pane ids, so the saved string restores the original
# layout exactly.
zen_enter_session() {
  local pane=$1 session window index layout path cols rows pindex zsession placeholder

  { read -r session; read -r window; read -r index; read -r pindex
    read -r cols; read -r rows; read -r layout; read -r path; } <<< "$(zen_tmux display-message -p -t "$pane" \
    "#{session_name}
#{window_id}
#{window_index}
#{pane_index}
#{window_width}
#{window_height}
#{window_layout}
#{pane_current_path}")"

  zsession=$(zen_session_name "$session" "$index")

  if zen_tmux has-session -t "=$zsession"; then
    zen_tmux display-message "zen: session $zsession is already there"
    return 1
  fi

  # Give the new session the size of the window we came from. A detached
  # new-session takes default-size, which is 80x24. The gutters would then be
  # sized for an 80 column window, and switch-client would resize the window and
  # spoil them. tmux does not keep the proportions when it resizes a window.
  zen_tmux new-session -d -s "$zsession" -c "$path" -x "$cols" -y "$rows" || return 1
  # Claim it at once, so every later kill can check ownership.
  zen_tmux set -t "$zsession" @zen_owned 1

  # new-session makes a placeholder pane. Note it, move the real pane in, then
  # kill the placeholder. This leaves the real pane alone in the window.
  placeholder=$(zen_tmux list-panes -t "$zsession:" -F '#{pane_id}' | head -1)
  if ! zen_tmux join-pane -h -s "$pane" -t "$zsession:"; then
    zen_kill_owned_session "$zsession"
    return 1
  fi
  [ -n "$placeholder" ] && zen_tmux kill-pane -t "$placeholder"

  zen_tmux \
    set -t "$zsession" @zen_origin_session "$session" ';' \
    set -t "$zsession" @zen_origin_window "$window" ';' \
    set -t "$zsession" @zen_origin_layout "$layout" ';' \
    set -t "$zsession" @zen_origin_index "$pindex"

  # Switch first, then lay out. The window takes the size of the attached client
  # when the client switches to it, so the gutter arithmetic must run after that.
  zen_switch_client "$zsession"
  zen_apply_layout "$pane"
}

# Switch the client that pressed the key. Name the client if the caller knows it.
# More than one client can be attached, and a bare switch-client moves whichever
# client tmux thinks is current, which may be a different one.
zen_switch_client() {
  if [ -n "${ZEN_CLIENT:-}" ]; then
    zen_tmux switch-client -c "$ZEN_CLIENT" -t "$1" && return 0
  fi
  zen_tmux switch-client -t "$1"
}

# Move the pane home, restore the layout of the original window, and kill the
# temporary session. tmux kills a session when its last window closes, so the
# kill-session call is only a safety net.
# join-pane always puts the pane at the end of the window. Move it back to the
# place it had before. select-layout gives the geometry to the panes in the order
# they are in now, so without this the panes come back in each other's places
# even though every size is right.
zen_restore_pane_order() {
  local window=$1 pane=$2 want=$3 count swaps i
  case "$want" in '' | *[!0-9]*) return 0 ;; esac
  count=$(zen_tmux display-message -p -t "$window" '#{window_panes}')
  case "$count" in '' | *[!0-9]*) return 0 ;; esac
  swaps=$(( count - 1 - want ))
  i=0
  while [ "$i" -lt "$swaps" ]; do
    zen_tmux swap-pane -d -U -t "$pane" || return 0
    i=$(( i + 1 ))
  done
  return 0
}

# Kill a session only if zen mode made it. Nothing else may be killed. A test
# once called zen_exit_session with a real session name, and the kill at the end
# destroyed that session and every process in it. The @zen_owned option is the
# proof of ownership, and it is set as soon as the session is made.
zen_kill_owned_session() {
  local s=${1:-}
  [ -n "$s" ] || return 0
  [ "$(zen_tmux show -qv -t "$s" @zen_owned)" = "1" ] || return 0
  zen_tmux kill-session -t "=$s"
}

zen_exit_session() {
  local pane=$1 zsession=$2 osession owindow olayout oindex

  # Refuse to touch a session that zen mode does not own, and refuse to move the
  # pane if the record of where it came from is missing.
  if [ "$(zen_tmux show -qv -t "$zsession" @zen_owned)" != "1" ]; then
    zen_tmux display-message "zen: $zsession is not a zen session"
    return 1
  fi
  osession=$(zen_tmux show -qv -t "$zsession" @zen_origin_session)
  owindow=$(zen_tmux show -qv -t "$zsession" @zen_origin_window)
  olayout=$(zen_tmux show -qv -t "$zsession" @zen_origin_layout)
  oindex=$(zen_tmux show -qv -t "$zsession" @zen_origin_index)
  if [ -z "$owindow" ] || [ -z "$osession" ]; then
    zen_tmux display-message "zen: no record of where the pane came from"
    return 1
  fi

  zen_clear_layout "$pane"

  # If the original window is gone, keep the pane where it is. A stranded pane
  # is better than a lost one.
  if ! zen_tmux join-pane -s "$pane" -t "$owindow"; then
    zen_tmux set -u -t "$zsession" @zen_owned
    zen_tmux display-message "zen: the original window is gone, the pane stays in $zsession"
    return 1
  fi
  zen_restore_pane_order "$owindow" "$pane" "$oindex"
  [ -n "$olayout" ] && zen_tmux select-layout -t "$owindow" "$olayout"
  zen_switch_client "$osession"
  zen_tmux select-pane -t "$pane"
  zen_kill_owned_session "$zsession"
  return 0
}

# --- commands ------------------------------------------------------------

# Take the lock, toggle, then give the lock back. The work is in a second
# function so that every early return in it still gives the lock back. Keep the
# lock here, not in main, so no caller can forget it.
zen_toggle() {
  local rc
  zen_lock || return 0
  zen_toggle_locked "$@"
  rc=$?
  zen_unlock
  return "$rc"
}

zen_toggle_locked() {
  local pane=${1:-} term=${2:-} panes=${3:-1} session before
  ZEN_CLIENT=${4:-}

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
  local window=${1:-} session active
  [ -n "$window" ] || return 0
  # Read both values in one call. This runs on every window change, so keep it
  # to a single round trip. Name the session: more than one client can be
  # attached, and the current session may belong to another client.
  { read -r session; read -r active; } <<< "$(zen_tmux display-message -p -t "$window" \
    "#{session_name}
#{@zen_active}")"
  [ -n "$session" ] || return 0
  if [ -n "$active" ]; then
    zen_tmux set -t "$session" status off
  else
    zen_tmux set -u -t "$session" status
  fi
  return 0
}

# Drop the font override if no window is in zen mode. tmux forgets the zen
# options when the server stops, but the font file stays on the disk. Without
# this, a server that stops during zen mode leaves every new Ghostty window at
# the zen font size, and nothing tells you why. The tmux configuration runs this
# when the server starts.
zen_clean() {
  local active
  active=$(zen_tmux list-windows -a -F '#{@zen_active}' 2>/dev/null | grep -c .)
  [ "${active:-0}" -eq 0 ] || return 0
  zen_font reset
}

main() {
  case "${1:-}" in
    # sync runs from a hook on every window change, so it must never wait for a
    # lock or contend with a toggle. It only reads state and sets the status bar.
    sync) zen_sync_status "${2:-}" ;;
    clean) zen_clean ;;
    # zen_toggle takes the lock itself.
    *) zen_toggle "${1:-}" "${2:-}" "${3:-}" "${4:-}" ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
