#!/usr/bin/env bash
# Claude Code status line: [vim mode] | model | ctx | worktree | branch | rate limits
input=$(cat)

dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$dir" ] && dir="$PWD"

# Git-derived worktree name + branch (works for linked worktrees too)
wt=""
br=""
if toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
  wt=$(basename "$toplevel")
  br=$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null \
       || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
fi

# Everything except the vim-mode indicator comes from the status line JSON
rest=$(printf '%s' "$input" | jq -r --arg wt "$wt" --arg br "$br" '
  [
    .model.display_name,
    "ctx:\(.context_window.used_percentage // 0)%",
    (if $wt != "" then "wt:\($wt)" else null end),
    (if $br != "" then "br:\($br)" else null end),
    (if .rate_limits.five_hour then
       (if .rate_limits.five_hour.used_percentage > 50
        then "5h:\(.rate_limits.five_hour.used_percentage | round)% (back at \(.rate_limits.five_hour.resets_at | strflocaltime("%H:%M")))"
        else "5h:\(.rate_limits.five_hour.used_percentage | round)%" end)
     else null end),
    (if .rate_limits.seven_day then "7d:\(.rate_limits.seven_day.used_percentage | round)%" else null end)
  ]
  | map(select(. != null)) | join("  |  ")')

# Vim-mode indicator: blue (#78B0FF) for INSERT, gray for everything else
mode=$(printf '%s' "$input" | jq -r '.vim.mode // empty')
if [ -n "$mode" ]; then
  reset=$'\033[0m'
  if [ "$mode" = "INSERT" ]; then
    color=$'\033[38;2;120;176;255m'   # #78B0FF
  else
    color=$'\033[38;2;128;128;128m'   # gray
  fi
  printf '%s%s%s  |  %s\n' "$color" "$mode" "$reset" "$rest"
else
  printf '%s\n' "$rest"
fi
