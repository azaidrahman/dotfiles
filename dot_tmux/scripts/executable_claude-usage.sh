#!/bin/bash
# prefix+u : render `claude -p /usage` as labeled TUI percentage bars.
# Parses each "Label: N% used · resets ..." line into a colored bar.
#
# `claude -p /usage` cold-boots the CLI + a network call (~1.5-2s), so:
#   1. if a cached render exists, draw it instantly (marked stale),
#   2. otherwise show a "Loading…" line,
#   3. then fetch fresh, overwrite the cache, and redraw.

set -u

CACHE="${TMPDIR:-/tmp}/claude-usage.cache"

c_reset=$'\033[0m'; c_dim=$'\033[2m'; c_bold=$'\033[1m'

color_for() { # pct -> green/yellow/red
  local p=$1
  if   (( p >= 90 )); then printf '\033[31m'
  elif (( p >= 70 )); then printf '\033[33m'
  else                     printf '\033[32m'
  fi
}

to_countdown() { # "Jun 22 at 4pm (Asia/Kuala_Lumpur)" -> "in 2h 15m" (empty on parse failure)
  local s=$1 raw mday t yr epoch now diff d h m
  raw=${s%% (*}        # drop trailing " (tz)"
  raw=${raw/ at / }    # "Jun 22 4pm"
  mday=${raw% *}       # "Jun 22"
  t=${raw##* }         # "4pm" or "11:30am"
  [[ $t != *:* ]] && t=$(printf '%s' "$t" | sed -E 's/^([0-9]+)(am|pm)$/\1:00\2/')  # 4pm -> 4:00pm
  yr=$(date +%Y)
  epoch=$(date -j -f "%b %d %Y %I:%M%p" "$mday $yr $t" +%s 2>/dev/null) || return
  [ -z "$epoch" ] && return
  now=$(date +%s)
  (( epoch < now - 86400 )) && epoch=$(date -j -f "%b %d %Y %I:%M%p" "$mday $((yr+1)) $t" +%s 2>/dev/null)  # year wrap
  diff=$(( epoch - now ))
  (( diff <= 0 )) && { printf 'now'; return; }
  d=$(( diff / 86400 )); h=$(( (diff % 86400) / 3600 )); m=$(( (diff % 3600) / 60 ))
  if   (( d > 0 )); then printf 'in %dd %dh' "$d" "$h"
  elif (( h > 0 )); then printf 'in %dh %dm' "$h" "$m"
  else                   printf 'in %dm' "$m"
  fi
}

repeat() { # char count -> char repeated count times (0-safe)
  local ch=$1 n=$2 out=''
  while (( n-- > 0 )); do out+=$ch; done
  printf '%s' "$out"
}

bar() { # label pct reset
  local label=$1 pct=$2 reset=$3
  (( pct > 100 )) && pct=100
  local width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
  local bar_w=$(( width - 38 ))
  (( bar_w < 10 )) && bar_w=10
  (( bar_w > 50 )) && bar_w=50
  local fill=$(( pct * bar_w / 100 ))
  local empty=$(( bar_w - fill ))
  local col; col=$(color_for "$pct")
  printf '  %-26s ' "$label"
  printf '%s%s%s%s%s' "$col" "$(repeat █ "$fill")" "$c_dim" "$(repeat ░ "$empty")" "$c_reset"
  printf ' %s%3d%%%s' "$c_bold" "$pct" "$c_reset"
  if [ -n "$reset" ]; then
    printf ' %sresets %s' "$c_dim" "$reset"
    local cd; cd=$(to_countdown "$reset")
    [ -n "$cd" ] && printf ' · %s' "$cd"
    printf '%s' "$c_reset"
  fi
  printf '\n'
}

render() { # raw-text status-note
  local raw=$1 note=$2 found=0 line
  clear 2>/dev/null
  echo
  printf '  %sClaude Code usage%s  %s%s%s\n\n' "$c_bold" "$c_reset" "$c_dim" "$note" "$c_reset"
  while IFS= read -r line; do
    if [[ $line =~ ^(.+):\ *([0-9]+)%\ used(\ *·\ *resets\ (.*))?$ ]]; then
      bar "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]:-}"
      found=1
    fi
  done <<< "$raw"
  (( found )) || printf '%s\n' "$raw"
}

# 1. instant draw from cache (or a loading placeholder)
if [[ -s $CACHE ]]; then
  render "$(cat "$CACHE")" "(cached — refreshing…)"
else
  clear 2>/dev/null
  echo
  printf '  %sClaude Code usage%s\n\n  %sLoading…%s\n' "$c_bold" "$c_reset" "$c_dim" "$c_reset"
fi

# 2. fetch fresh, cache, redraw
FRESH=$(claude -p /usage 2>&1)
printf '%s\n' "$FRESH" > "$CACHE"
render "$FRESH" ""

echo
printf '  %s[any key to close]%s' "$c_dim" "$c_reset"
old_stty=$(stty -g 2>/dev/null)
stty -echo -icanon min 1 time 0 2>/dev/null
dd bs=1 count=1 >/dev/null 2>&1
[ -n "$old_stty" ] && stty "$old_stty" 2>/dev/null
