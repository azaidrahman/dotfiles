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

# litellm_key : the proxy master key. Prefer the env var (present when sourced
# from a zsh that read ~/.zshenv); fall back to extracting it from secrets.zsh,
# because this popup runs as a fresh bash shell that never sourced ~/.zshenv.
litellm_key() {
  if [ -n "${LITELLM_MASTER_KEY:-}" ]; then printf '%s' "$LITELLM_MASTER_KEY"; return; fi
  local f="$HOME/.config/zsh/secrets.zsh"
  [ -r "$f" ] || return
  grep -E '^export[[:space:]]+LITELLM_MASTER_KEY=' "$f" | head -1 \
    | sed -E 's/^export[[:space:]]+LITELLM_MASTER_KEY=//; s/^["'\'']//; s/["'\'']$//'
}

# litellm_curl <base> <key> <path> : authenticated GET against the proxy.
litellm_curl() {
  curl -fsS -m 5 -H "Authorization: Bearer $2" "$1$3" 2>/dev/null
}

# cost_blob <models_json> <spend_json> <logs_json> <cutoff_date> : fold the
# proxy's real ledger into a cacheable, render-ready blob (pure; no network).
#   TOTALALL <usd>            grand total across all logged requests
#   TOTAL7D  <usd>            spend on/after <cutoff_date> (YYYY-MM-DD)
#   MODEL    <usd>\t<model>   per-model spend, one line each
cost_blob() {
  local mj=$1 sj=$2 lj=$3 cut=$4 all sevend
  all=$(printf '%s' "$sj"  | jq -r '.spend // 0' 2>/dev/null); all=${all:-0}
  sevend=$(printf '%s' "$lj" | jq -r --arg c "$cut" \
    '[.[] | select(.date >= $c) | .spend] | add // 0' 2>/dev/null); sevend=${sevend:-0}
  printf 'TOTALALL %s\nTOTAL7D %s\n' "$all" "$sevend"
  # only models with real spend; drop the "vertex_ai/" provider prefix for width
  printf '%s' "$mj" | jq -r '
    [.[] | select((.total_spend // 0) > 0)] | sort_by(-.total_spend)[]
    | "MODEL \(.total_spend)\t\(.model | sub("^[a-z_]+/"; ""))"' 2>/dev/null
}

# render_cost <blob> : draw the LiteLLM ledger — one bar per model (all-time
# spend), then last-7-day and all-time totals. <blob> is cost_blob's output.
render_cost() {
  local blob=$1 total_all total7d models
  total_all=$(printf '%s\n' "$blob" | awk '$1=="TOTALALL"{print $2; exit}')
  total7d=$( printf '%s\n' "$blob" | awk '$1=="TOTAL7D"{print $2; exit}')
  models=$(  printf '%s\n' "$blob" | sed -n 's/^MODEL //p')   # lines: "<spend>\t<model>"

  clear 2>/dev/null
  echo
  printf '  %sCost · LiteLLM ledger%s\n' "$c_bold" "$c_reset"
  printf '  provider: %s\n\n' "$(provider_tag)"

  if [ -z "$models" ]; then
    printf '  %sno spend recorded by the proxy%s\n' "$c_dim" "$c_reset"
    return
  fi

  local max; max=$(printf '%s\n' "$models" | awk -F'\t' \
    'BEGIN{m=0}{if($1+0>m)m=$1+0}END{if(m<=0)m=1; print m}')
  local width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
  local bar_w=$(( width - 42 )); (( bar_w < 8 )) && bar_w=8; (( bar_w > 32 )) && bar_w=32

  local spend model pct fill empty
  while IFS=$'\t' read -r spend model; do
    [ -z "$model" ] && continue
    pct=$(awk -v v="$spend" -v m="$max" 'BEGIN{printf "%d", (v/m)*100}')
    fill=$(( pct * bar_w / 100 )); (( fill < 0 )) && fill=0; (( fill > bar_w )) && fill=bar_w
    empty=$(( bar_w - fill ))
    printf '  %-24s %s%s%s%s%s %s$%0.2f%s\n' \
      "${model:0:24}" "$(color_for "$pct")" "$(repeat █ "$fill")" "$c_dim" "$(repeat ░ "$empty")" \
      "$c_reset" "$c_bold" "$spend" "$c_reset"
  done <<< "$models"

  printf '  %s%s%s\n' "$c_dim" "$(repeat ─ $(( bar_w + 26 )))" "$c_reset"
  printf '  %-24s %*s%s$%0.2f%s\n'      "Total · last 7 days" "$bar_w" "" "$c_bold" "${total7d:-0}" "$c_reset"
  printf '  %s%-24s %*s$%0.2f%s\n' "$c_dim" "all-time" "$bar_w" "" "${total_all:-0}" "$c_reset"
}

COST_CACHE="${TMPDIR:-/tmp}/claude-cost.cache"

cost_main() {
  # instant draw from cache (the render-ready blob is what we cache)
  if [[ -s $COST_CACHE ]]; then
    render_cost "$(cat "$COST_CACHE")"
    printf '\n  %s(cached — refreshing…)%s\n' "$c_dim" "$c_reset"
  else
    clear 2>/dev/null
    echo
    printf '  %sCost · LiteLLM ledger%s\n\n  %sLoading…%s\n' "$c_bold" "$c_reset" "$c_dim" "$c_reset"
  fi

  # fresh pull from the proxy's own ledger (the real spend it logged)
  local base key cutoff mj sj lj
  base=$(litellm_base); key=$(litellm_key)
  cutoff=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
  mj=$(litellm_curl "$base" "$key" "/global/spend/models")
  sj=$(litellm_curl "$base" "$key" "/global/spend")
  lj=$(litellm_curl "$base" "$key" "/global/spend/logs")

  if [ -z "$mj" ] && [ -z "$sj" ]; then
    clear 2>/dev/null
    echo
    printf '  %sCost · LiteLLM ledger%s\n' "$c_bold" "$c_reset"
    printf '  provider: %s\n\n' "$(provider_tag)"
    printf '  %sproxy unreachable — could not fetch spend%s\n' "$c_dim" "$c_reset"
  else
    local fresh; fresh=$(cost_blob "$mj" "$sj" "$lj" "$cutoff")
    printf '%s\n' "$fresh" > "$COST_CACHE"
    render_cost "$fresh"
  fi

  echo
  printf '  %s[any key to close]%s' "$c_dim" "$c_reset"
  local old_stty; old_stty=$(stty -g 2>/dev/null)
  stty -echo -icanon min 1 time 0 2>/dev/null
  dd bs=1 count=1 >/dev/null 2>&1
  [ -n "$old_stty" ] && stty "$old_stty" 2>/dev/null
}

# session_provider : what the invoking pane's claude is routing through, read
# from the per-pane @claude_provider marker that `cv` sets. Empty if unknown.
# SRC_PANE is the pane id passed by the keybinding (see keys.conf).
session_provider() {
  [ -n "${SRC_PANE:-}" ] || return
  tmux show-options -pqv -t "$SRC_PANE" @claude_provider 2>/dev/null
}

provider_tag() {
  if [ "$(session_provider)" = "litellm" ]; then
    printf '\033[35mLiteLLM\033[0m \033[2m(%s)\033[0m' "$(litellm_base)"
  elif [ -n "${CLAUDE_CODE_USE_VERTEX:-}" ]; then
    printf '\033[34mVertex AI (direct)\033[0m'
  else
    printf '\033[36mAnthropic API\033[0m'
  fi
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
  printf '  %sClaude Code usage%s  %s%s%s\n' "$c_bold" "$c_reset" "$c_dim" "$note" "$c_reset"
  printf '  provider: %s\n\n' "$(provider_tag)"
  while IFS= read -r line; do
    if [[ $line =~ ^(.+):\ *([0-9]+)%\ used(\ *·\ *resets\ (.*))?$ ]]; then
      bar "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]:-}"
      found=1
    fi
  done <<< "$raw"
  (( found )) || printf '%s\n' "$raw"
}

usage_main() {
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
}

litellm_base() {
  if [[ "$(hostname -s)" == onyx* ]]; then
    printf 'http://localhost:4000'
  else
    printf 'http://onyx.tail5d740c.ts.net:4000'
  fi
}

# Decide the view by whether THIS session routes through LiteLLM (per-pane
# marker), NOT by whether the proxy happens to be alive — the proxy is always
# reachable over Tailscale, so liveness would show cost even for a plain
# subscription session.
main() {
  SRC_PANE="${1:-}"
  if [ "$(session_provider)" = "litellm" ]; then
    cost_main
  else
    usage_main
  fi
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
