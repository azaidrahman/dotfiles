#!/usr/bin/env bash
# Source for the `tmux-windows` television channel.
# Emits display-ready lines with ANSI in the dot. tv renders the line directly
# (no `display` template) so ANSI survives; output/preview/actions extract the
# tmux target via `strip_ansi|split:\t:1`.
#
# Per-line format (tab-separated columns):
#   <dot>\t<session>:<idx>\t<window_name>
set -u

ALERTS="$HOME/.tmux/alerts"

tmux list-windows -a -F '#{window_stack_index}	#{session_last_attached}	#{session_name}	#{window_index}	#{window_name}	#{pane_current_command}' \
  | sort -t$'\t' -k1,1n -k2,2nr \
  | cut -f3- \
  | awk -F'\t' -v A="$ALERTS" '
      BEGIN {
        while ((getline l < A) > 0) {
          split(l, p, "\t")
          pend[p[1]] = p[3]
        }
        YEL = "\033[1;33m"
        RED = "\033[1;31m"
        DIM = "\033[2;37m"
        RST = "\033[0m"
      }
      {
        sess = $1; idx = $2; wname = $3
        if (sess == "mobile" || sess == "quickterminal") next   # reachable via prefix+F (tv channels)
        key  = sess ":" idx
        if (key in pend) {
          t = pend[key]
          if      (t == "BELL")     dot = RED "●" RST
          else if (t == "ACTIVITY") dot = DIM "●" RST
          else                      dot = YEL "●" RST
        } else {
          dot = " "
        }
        printf "%s\t%s:%s\t%s\n", dot, sess, idx, wname
      }
    '
