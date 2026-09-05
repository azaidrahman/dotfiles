#!/usr/bin/env bash
# Show a popup menu of windows from OTHER sessions that can be linked into the
# mobile session. Selecting an item links that real, live window into mobile and
# (no -d on link-window) jumps onto it. Bound to prefix+b in visual-mobile.conf,
# which passes the triggering client so display-menu knows where to draw.
#
#   arg1                = triggering client name (#{client_name})
#   MOBILE_SESSION      = target session (default: mobile)
#   MOBILE_LINK_DRYRUN  = if set, print "<window_id>\t<label>" candidates and
#                         exit instead of showing the menu (for tests)
set -u

CLIENT="${1:-}"
SESSION="${MOBILE_SESSION:-mobile}"

# Window-level options copied from mobile's own window onto a borrowed window so
# it renders with mobile's minimal profile instead of the desktop theme. These
# are window (not session) options, so they have no session-wide default and must
# be set per window. Keep in sync with mobile-unlink-all.sh (which unsets them)
# and the `set -t mobile …` block in conf.d/visual-mobile.conf.
STRIP_OPTS="window-style window-active-style pane-border-status pane-border-style pane-active-border-style"

# Borrow mode (invoked by the menu items via run-shell): link one window into
# mobile, then copy mobile's own window styling onto it. Window options are
# shared across the link, so mobile-unlink-all.sh unsets them again on detach.
if [ "${1:-}" = "borrow" ]; then
  wid="${2:-}"
  [ -z "$wid" ] && exit 0
  tmux link-window -s "$wid" -t "$SESSION:" 2>/dev/null || exit 0
  ref=$(tmux list-windows -t "=$SESSION" -F '#{window_linked} #{window_id}' \
        | awk '$1 == 0 { print $2; exit }')   # mobile's own (unlinked) window
  if [ -n "$ref" ]; then
    for opt in $STRIP_OPTS; do
      val=$(tmux show-options -w -t "$ref" -v "$opt" 2>/dev/null)
      [ -n "$val" ] && tmux set -w -t "$wid" "$opt" "$val"
    done
  fi
  exit 0
fi

# Window-ids already in mobile (its own + already-borrowed), newline separated.
in_mobile=$(tmux list-windows -t "=$SESSION" -F '#{window_id}' 2>/dev/null)

# Candidate windows across all sessions, most-recently-active first.
# Columns: activity \t window_id \t session \t index \t name \t command
candidates=$(tmux list-windows -a -F \
  '#{window_activity}	#{window_id}	#{session_name}	#{window_index}	#{window_name}	#{pane_current_command}' \
  | sort -t$'\t' -k1,1nr \
  | cut -f2-)

dry="${MOBILE_LINK_DRYRUN:-}"
items=()
count=0
while IFS=$'\t' read -r wid sess idx name cmd; do
  [ -z "$wid" ] && continue
  printf '%s\n' "$in_mobile" | grep -qx "$wid" && continue   # skip windows in mobile
  label="$sess:$idx  $name ($cmd)"
  if [ -n "$dry" ]; then
    printf '%s\t%s\n' "$wid" "$label"
    continue
  fi
  key=""
  if [ "$count" -lt 9 ]; then key=$((count + 1)); fi
  # Escape '#' so tmux doesn't treat the menu label as a #{...}/#[...] format.
  items+=("${label//#/##}" "$key" "run-shell '~/.tmux/scripts/mobile-link-menu.sh borrow $wid'")
  count=$((count + 1))
done <<< "$candidates"

# dry-run: candidates already printed above; nothing to render
[ -n "$dry" ] && exit 0

if [ "${#items[@]}" -eq 0 ]; then
  tmux display-message "No other windows to link"
  exit 0
fi

tmux display-menu -c "$CLIENT" -T " Link window → $SESSION " -x C -y C "${items[@]}"
