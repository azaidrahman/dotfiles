#!/usr/bin/env bash
# Claude Code status line: [vim mode] | model | effort | ctx | worktree | branch | rate limits
input=$(cat)

dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$dir" ] && dir="$PWD"

wt=""
br=""
if gitinfo=$(git -C "$dir" rev-parse --show-toplevel --abbrev-ref HEAD 2>/dev/null); then
  wt=$(basename "$(printf '%s' "$gitinfo" | sed -n 1p)")
  br=$(printf '%s' "$gitinfo" | sed -n 2p)
fi

show_cost="false"
[ -n "${CLAUDE_CODE_USE_VERTEX:-}" ] && show_cost="true"

# jq pass: emit fields joined by \x01 (non-whitespace) so IFS read preserves empty fields.
# Tab (\t) collapses consecutive delimiters in bash IFS read; \x01 does not.
mode=$(printf '%s' "$input" | jq -r '.vim.mode // ""')
out=$(printf '%s' "$input" | jq -r --arg wt "$wt" --arg br "$br" --arg show_cost "$show_cost" '
  [
    (.model.display_name // ""),
    (.effort.level // ""),
    (if $show_cost == "true" and (.cost.total_cost_usd != null) then (.cost.total_cost_usd | tostring) else "" end),
    ((.context_window.used_percentage // 0) | tostring),
    $wt,
    $br,
    (if .rate_limits.five_hour then (.rate_limits.five_hour.used_percentage | round | tostring) else "" end),
    (if .rate_limits.five_hour then (.rate_limits.five_hour.resets_at | strflocaltime("%H:%M")) else "" end),
    (if .rate_limits.seven_day then (.rate_limits.seven_day.used_percentage | round | tostring) else "" end)
  ] | join("")')

IFS=$'\x01' read -r model effort cost_raw ctx_pct wt br five_h_pct five_h_resets seven_d_pct <<< "$out"

# ── Color helpers (256-color for tmux stability) ───────────────────────────────

reset=$'\033[0m'

color_for_model() {
  local lc; lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    *haiku*)  printf '\033[38;5;82m'  ;;  # green   — cheapest
    *sonnet*) printf '\033[38;5;226m' ;;  # yellow
    *opus*)   printf '\033[38;5;208m' ;;  # orange
    *fable*)  printf '\033[38;5;196m' ;;  # red     — most expensive
    *)        printf '\033[38;5;244m' ;;
  esac
}

color_for_effort() {
  local lc; lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    low|minimal)   printf '\033[38;5;82m'  ;;  # green
    medium|normal) printf '\033[38;5;226m' ;;  # yellow
    high)          printf '\033[38;5;208m' ;;  # orange
    max|highest)   printf '\033[38;5;196m' ;;  # red
    *)             printf '\033[38;5;244m' ;;
  esac
}

# color_for_rate <pct>: gray below 50%, green→red from 50% to 100%
color_for_rate() {
  local pct=$1
  if   [ "$pct" -lt 50 ]; then printf '\033[38;5;244m'  # gray  — not worth highlighting yet
  elif [ "$pct" -lt 70 ]; then printf '\033[38;5;82m'   # green
  elif [ "$pct" -lt 85 ]; then printf '\033[38;5;226m'  # yellow
  elif [ "$pct" -lt 95 ]; then printf '\033[38;5;208m'  # orange
  else                         printf '\033[38;5;196m'  # red
  fi
}

# color_for_cost <usd>: gray below $20, green→red from $20 to $100+
color_for_cost() {
  local tier
  tier=$(awk -v u="$1" 'BEGIN {
    if      (u <  20) print "gray"
    else if (u <  50) print "green"
    else if (u <  75) print "yellow"
    else if (u < 100) print "orange"
    else              print "red"
  }')
  case "$tier" in
    gray)   printf '\033[38;5;244m' ;;
    green)  printf '\033[38;5;82m'  ;;
    yellow) printf '\033[38;5;226m' ;;
    orange) printf '\033[38;5;208m' ;;
    red)    printf '\033[38;5;196m' ;;
  esac
}

# ── Build segments ─────────────────────────────────────────────────────────────

sep="  |  "
segments=()

[ -n "$model"  ] && segments+=("$(color_for_model  "$model")${model}${reset}")
[ -n "$effort" ] && segments+=("$(color_for_effort "$effort")eff:${effort}${reset}")

if [ -n "$cost_raw" ]; then
  cost_display=$(awk -v u="$cost_raw" 'BEGIN { printf "$%.2f", u+0 }')
  segments+=("$(color_for_cost "$cost_raw")${cost_display}${reset}")
fi

segments+=("ctx:${ctx_pct}%")

[ -n "$wt" ] && segments+=("wt:${wt}")
[ -n "$br" ] && segments+=("br:${br}")

if [ -n "$five_h_pct" ]; then
  label="5h:${five_h_pct}%"
  [ "$five_h_pct" -gt 50 ] && [ -n "$five_h_resets" ] && label="${label} (back at ${five_h_resets})"
  segments+=("$(color_for_rate "$five_h_pct")${label}${reset}")
fi

if [ -n "$seven_d_pct" ]; then
  segments+=("$(color_for_rate "$seven_d_pct")7d:${seven_d_pct}%${reset}")
fi

# ── Assemble ───────────────────────────────────────────────────────────────────

result=""
for i in "${!segments[@]}"; do
  if [ "$i" -eq 0 ]; then
    result="${segments[$i]}"
  else
    result="${result}${sep}${segments[$i]}"
  fi
done

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
  printf '%s%s\033[0m  |  %s' "$color" "$mode" "$result"
else
  printf '%s' "$result"
fi
