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

tmux list-windows -a -F '#{window_stack_index}	#{session_last_attached}	#{session_name}	#{window_index}	#{window_name}	#{@claude_state}	#{pane_current_command}' \
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
        GRN = "\033[1;32m"
        CYN = "\033[1;36m"
        MAG = "\033[1;35m"
        DIM = "\033[2;37m"
        RST = "\033[0m"
      }
      {
        sess = $1; idx = $2; wname = $3; state = $4
        if (sess == "mobile" || sess == "quickterminal") next   # reachable via prefix+F (tv channels)
        # Claude state lives in the @claude_state window option (set by
        # notify-tmux.sh): color the row by it. Names are kept clean now, but
        # strip any legacy/manual leading glyph just in case.
        col = ""
        if      (state == "working")    col = CYN
        else if (state == "permission") col = RED
        else if (state == "question")   col = MAG
        else if (state == "idle")       col = YEL
        else if (state == "done")       col = GRN
        sub(/^[^[:alnum:]]+[[:space:]]*/, "", wname)
        # No live Claude state? Fall back to a logged alert (bell/activity) if any.
        key = sess ":" idx
        if (col == "" && key in pend) {
          t = pend[key]
          if      (t == "BELL")     col = RED
          else if (t == "ACTIVITY") col = DIM
          else                      col = YEL
        }
        # tv strips ANSI before extracting the target, so coloring the whole row is
        # safe. Keep an (empty) first column so split:\t:1 still yields session:idx.
        line = " \t" sess ":" idx "\t" wname
        if (col != "") printf "%s%s%s\n", col, line, RST
        else           printf "%s\n", line
        n++
      }
      END {
        # Only mobile/quickterminal exist — nothing to switch to. Emit a
        # placeholder with an empty target so select/preview no-op gracefully.
        if (n == 0) printf "%s\t\t%s\n", DIM "-" RST, DIM "no working sessions" RST
      }
    '
