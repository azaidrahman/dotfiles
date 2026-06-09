#!/usr/bin/env bash
# Claude Code status line: [vim mode] | model | effort | ctx | worktree | branch | rate limits
input=$(cat)

dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$dir" ] && dir="$PWD"

# Git worktree name + branch in a single git call (line 1 = toplevel, line 2 = branch)
wt=""
br=""
if gitinfo=$(git -C "$dir" rev-parse --show-toplevel --abbrev-ref HEAD 2>/dev/null); then
  wt=$(basename "$(printf '%s' "$gitinfo" | sed -n 1p)")
  br=$(printf '%s' "$gitinfo" | sed -n 2p)
fi

# Single jq pass: emit "<vim mode>\t<rest of segments>"
out=$(printf '%s' "$input" | jq -r --arg wt "$wt" --arg br "$br" '
  (.vim.mode // "") + "\t" + ([
    .model.display_name,
    (if .effort.level then "eff:\(.effort.level)" else null end),
    "ctx:\(.context_window.used_percentage // 0)%",
    (if $wt != "" then "wt:\($wt)" else null end),
    (if $br != "" then "br:\($br)" else null end),
    (if .rate_limits.five_hour then
       (if .rate_limits.five_hour.used_percentage > 50
        then "5h:\(.rate_limits.five_hour.used_percentage | round)% (back at \(.rate_limits.five_hour.resets_at | strflocaltime("%H:%M")))"
        else "5h:\(.rate_limits.five_hour.used_percentage | round)%" end)
     else null end),
    (if .rate_limits.seven_day then "7d:\(.rate_limits.seven_day.used_percentage | round)%" else null end)
  ] | map(select(. != null)) | join("  |  "))')

mode=${out%%$'\t'*}
rest=${out#*$'\t'}

# Vim-mode indicator: blue for INSERT, gray otherwise.
# Deliberately 256-color (not 24-bit) and NO trailing newline:
#  - tmux here reports RGB=no, so a truecolor SGR gets re-downsampled every
#    repaint; an explicit 256-color code is tmux-native and stable per frame.
#  - a trailing \n makes Claude Code treat this as a 2-line status and redraw
#    both rows, which flickers/duplicates during generation.
if [ -n "$mode" ]; then
  if [ "$mode" = "INSERT" ]; then
    color=$'\033[38;5;75m'    # light blue (~#5fafff)
  else
    color=$'\033[38;5;244m'   # gray
  fi
  printf '%s%s\033[0m  |  %s' "$color" "$mode" "$rest"
else
  printf '%s' "$rest"
fi
