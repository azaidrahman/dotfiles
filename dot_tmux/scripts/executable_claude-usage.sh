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

to_epoch() { # "Jun 22 at 4pm (Asia/Kuala_Lumpur)" -> epoch seconds (empty on parse failure)
  local s=$1 raw mday t yr epoch now
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
  printf '%s' "$epoch"
}

# window_len <label> : the full length of a limit window, in seconds. The API
# reports only the reset time, so the length comes from the label: a session
# window is 5 hours, a weekly window is 7 days. Empty for an unknown label.
window_len() {
  local l; l=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$l" in
    *session*) printf '18000'  ;;   # 5h
    *week*)    printf '604800' ;;   # 7d
  esac
}

# window_noun <label> : the word for the window, used in the elapsed-time note.
window_noun() {
  local l; l=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$l" in
    *session*) printf 'session' ;;
    *week*)    printf 'week'    ;;
    *)         printf 'window'  ;;
  esac
}

# elapsed_pct <label> <reset-string> : how much of the window is gone, 0-100.
# Empty if the label or the reset time cannot be parsed.
elapsed_pct() {
  local len epoch now left p
  len=$(window_len "$1"); [ -n "$len" ] || return
  epoch=$(to_epoch "$2"); [ -n "$epoch" ] || return
  now=$(date +%s)
  left=$(( epoch - now ))
  (( left < 0 )) && left=0
  (( left > len )) && left=$len
  p=$(( (len - left) * 100 / len ))
  printf '%s' "$p"
}

to_countdown() { # "Jun 22 at 4pm (Asia/Kuala_Lumpur)" -> "in 2h 15m" (empty on parse failure)
  local s=$1 epoch now diff d h m
  epoch=$(to_epoch "$s"); [ -n "$epoch" ] || return
  now=$(date +%s)
  diff=$(( epoch - now ))
  (( diff <= 0 )) && { printf 'now'; return; }
  d=$(( diff / 86400 )); h=$(( (diff % 86400) / 3600 )); m=$(( (diff % 3600) / 60 ))
  if   (( d > 0 )); then printf 'in %dd %dh' "$d" "$h"
  elif (( h > 0 )); then printf 'in %dh %dm' "$h" "$m"
  else                   printf 'in %dm' "$m"
  fi
}

to_clock() { # "Jun 22 at 4pm (Asia/Kuala_Lumpur)" -> "4:00PM SUN 22-JUN" (empty on parse failure)
  local s=$1 epoch
  epoch=$(to_epoch "$s"); [ -n "$epoch" ] || return
  date -r "$epoch" '+%I:%M%p %a %d-%b' 2>/dev/null \
    | tr '[:lower:]' '[:upper:]' | sed -E 's/^0//'
}

# term_width : the popup's real column count. `tput cols` first — inside a
# display-popup, $COLUMNS can come in pre-exported as a stale "0" from the
# outer environment, and "${COLUMNS:-default}" only falls back on unset/empty,
# not on a literal 0, so trusting it here silently floors every bar to 10 wide.
# Do NOT redirect tput's stderr: with stdout captured by $(...), tput falls
# back to querying stderr for the controlling tty, and `2>/dev/null` kills
# that path too, silently returning the 80x24 default instead of the real size.
term_width() {
  local c; c=$(tput cols)
  if [[ $c =~ ^[0-9]+$ ]] && (( c > 0 )); then printf '%s' "$c"; return; fi
  if [[ ${COLUMNS:-0} =~ ^[0-9]+$ ]] && (( ${COLUMNS:-0} > 0 )); then printf '%s' "$COLUMNS"; return; fi
  printf '80'
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

# cost_blob <models_json> <spend_json> <logs_json> <cut7d> <cutMTD> <cutYTD> :
# fold the proxy's real ledger into a cacheable, render-ready blob (pure; no
# network). The three cutoffs are inclusive YYYY-MM-DD lower bounds summed from
# the daily logs.
#   TOTALALL <usd>            grand total across all logged requests
#   TOTAL7D  <usd>            spend on/after <cut7d>
#   TOTALMTD <usd>            spend on/after <cutMTD> (first of this month)
#   TOTALYTD <usd>            spend on/after <cutYTD> (first of this year)
#   MODEL    <usd>\t<model>   per-model spend, one line each
cost_blob() {
  local mj=$1 sj=$2 lj=$3 cut=$4 cutm=$5 cuty=$6 all
  all=$(printf '%s' "$sj"  | jq -r '.spend // 0' 2>/dev/null); all=${all:-0}
  # sum the daily logs on/after an inclusive YYYY-MM-DD cutoff (0 on failure)
  sum_since() { local s; s=$(printf '%s' "$lj" | jq -r --arg c "$1" \
    '[.[] | select(.date >= $c) | .spend] | add // 0' 2>/dev/null); printf '%s' "${s:-0}"; }
  printf 'TOTALALL %s\nTOTAL7D %s\nTOTALMTD %s\nTOTALYTD %s\n' \
    "$all" "$(sum_since "$cut")" "$(sum_since "$cutm")" "$(sum_since "$cuty")"
  # only models with real spend; drop the "vertex_ai/" provider prefix for width
  printf '%s' "$mj" | jq -r '
    [.[] | select((.total_spend // 0) > 0)] | sort_by(-.total_spend)[]
    | "MODEL \(.total_spend)\t\(.model | sub("^[a-z_]+/"; ""))"' 2>/dev/null
}

# render_cost <blob> : draw the LiteLLM ledger — one bar per model (all-time
# spend), then last-7-day / month-to-date / year-to-date / all-time totals.
# <blob> is cost_blob's output.
render_cost() {
  local blob=$1 total_all total7d totalmtd totalytd models
  total_all=$(printf '%s\n' "$blob" | awk '$1=="TOTALALL"{print $2; exit}')
  total7d=$( printf '%s\n' "$blob" | awk '$1=="TOTAL7D"{print $2; exit}')
  totalmtd=$(printf '%s\n' "$blob" | awk '$1=="TOTALMTD"{print $2; exit}')
  totalytd=$(printf '%s\n' "$blob" | awk '$1=="TOTALYTD"{print $2; exit}')
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
  local width=$(term_width)
  local bar_w=$(( width - 42 )); (( bar_w < 8 )) && bar_w=8; (( bar_w > 45 )) && bar_w=45

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
  printf '  %-24s %*s$%0.2f\n'          "month to date" "$bar_w" "" "${totalmtd:-0}"
  printf '  %-24s %*s$%0.2f\n'          "year to date"  "$bar_w" "" "${totalytd:-0}"
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
  local base key cutoff cutoff_m cutoff_y mj sj lj
  base=$(litellm_base); key=$(litellm_key)
  cutoff=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
  cutoff_m=$(date +%Y-%m-01)   # first of this month (BSD + GNU)
  cutoff_y=$(date +%Y-01-01)   # first of this year
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
    local fresh; fresh=$(cost_blob "$mj" "$sj" "$lj" "$cutoff" "$cutoff_m" "$cutoff_y")
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

LABEL_W=26   # width of the label column; the marker note aligns against it
BAR_CAP=70   # the bar never grows past this, however wide the terminal is

# ROW_FIXED_W : every cell of a usage row except the bar itself. The popup
# width comes from this sum, so a change to the reset format widens the box
# instead of wrapping the last characters onto the next line.
#   2  indent
#  +LABEL_W +1  the label column and the space after it
#  +5  " 100%"
#  +6  " ▲+100"
#  +37 " resets in Xh Xm (H:MMPM DDD DD-MON)"
ROW_FIXED_W=$(( 2 + LABEL_W + 1 + 5 + 6 + 37 ))

bar() { # label pct reset
  local label=$1 pct=$2 reset=$3
  (( pct > 100 )) && pct=100
  local width=$(term_width)
  local bar_w=$(( width - ROW_FIXED_W ))
  (( bar_w < 10 )) && bar_w=10
  (( bar_w > BAR_CAP )) && bar_w=$BAR_CAP
  local fill=$(( pct * bar_w / 100 ))
  local col; col=$(color_for "$pct")

  # elapsed : how much of the window has passed. It marks the "on pace" point —
  # if the fill is past the marker, you burn the budget faster than the clock.
  local elapsed mark=-1
  elapsed=$(elapsed_pct "$label" "$reset")
  if [ -n "$elapsed" ]; then
    mark=$(( elapsed * bar_w / 100 ))
    (( mark > bar_w - 1 )) && mark=$(( bar_w - 1 ))
    (( mark < 0 )) && mark=0
  fi

  printf '  %-*s ' "$LABEL_W" "$label"
  local i out=''
  for (( i = 0; i < bar_w; i++ )); do
    if   (( i == mark )); then out+="${c_bold}│${c_reset}"
    elif (( i < fill ));  then out+="${col}█${c_reset}"
    else                       out+="${c_dim}░${c_reset}"
    fi
  done
  printf '%s' "$out"
  printf ' %s%3d%%%s' "$c_bold" "$pct" "$c_reset"

  # pace delta : used% minus elapsed%. Positive means ahead of the clock.
  if [ -n "$elapsed" ]; then
    local d=$(( pct - elapsed ))
    if   (( d >= 3 ));  then printf ' \033[31m▲+%d\033[0m' "$d"
    elif (( d <= -3 )); then printf ' \033[32m▼%d\033[0m' "$d"
    else                     printf ' %s≈%s' "$c_dim" "$c_reset"
    fi
  fi

  if [ -n "$reset" ]; then
    local cd clk; cd=$(to_countdown "$reset"); clk=$(to_clock "$reset")
    if [ -n "$cd" ]; then
      if [ -n "$clk" ]; then printf ' %sresets %s (%s)%s' "$c_dim" "$cd" "$clk" "$c_reset"
      else                   printf ' %sresets %s%s' "$c_dim" "$cd" "$c_reset"
      fi
    else                     printf ' %sresets %s%s' "$c_dim" "$reset" "$c_reset"
    fi
  fi
  printf '\n'

  # second line : point at the marker and say what it means
  if [ -n "$elapsed" ]; then
    printf '  %*s %*s%s↑ %d%% of the %s elapsed%s\n' \
      "$LABEL_W" "" "$mark" "" "$c_dim" "$elapsed" "$(window_noun "$label")" "$c_reset"
  fi
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

# --- popup sizing --------------------------------------------------------
# `prefix+u` opens a fixed-content popup (a handful of bars, or a handful of
# model rows) but tmux's own -w/-h only understand terminal percentages, so a
# wide/tall terminal used to blow the popup up far past what the content
# needs. Instead we size the popup ourselves, in cells, to whichever view
# (usage vs cost) this pane is about to render.

# +2 for the popup border, which eats a column on each side.
USAGE_POPUP_W=$(( ROW_FIXED_W + BAR_CAP + 2 ))   # fits a full-cap bar plus its row
COST_POPUP_W=90      # fits a full-cap 45-char bar (see the -42 offset in render_cost)

# rows_for_usage : number of metric rows the cached /usage text will render.
# Falls back to 3 (session + week-all-models + one per-model line) with no
# cache yet, i.e. before the first fetch has ever completed.
rows_for_usage() {
  if [[ -s $CACHE ]]; then
    grep -cE '^.+: *[0-9]+% used' "$CACHE" 2>/dev/null || printf '3'
  else
    printf '3'
  fi
}

# rows_for_cost : number of model bars the cached ledger will render. Falls
# back to 6 with no cache yet.
rows_for_cost() {
  if [[ -s $COST_CACHE ]]; then
    local n; n=$(grep -c '^MODEL ' "$COST_CACHE" 2>/dev/null)
    printf '%s' "${n:-6}"
  else
    printf '6'
  fi
}

# size_for <pane_id> : "WxH" popup dimensions for whichever view this pane
# will render.
size_for() {
  SRC_PANE=$1
  if [ "$(session_provider)" = "litellm" ]; then
    printf '%dx%d' "$COST_POPUP_W" "$(( $(rows_for_cost) + 13 ))"
  else
    printf '%dx%d' "$USAGE_POPUP_W" "$(( $(rows_for_usage) * 2 + 8 ))"
  fi
}

# popup_main <pane_id> <cwd> : called from the keybinding (outside any popup)
# to open the popup at the size the view needs.
popup_main() {
  local pane=$1 cwd=$2 sz w h
  sz=$(size_for "$pane")
  w=${sz%x*}; h=${sz#*x}
  tmux display-popup -E -w "$w" -h "$h" -d "$cwd" -T ' Usage ' "$0 $pane"
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
  # display-popup does NOT expand formats in its command string, so the
  # keybinding's #{pane_id} arrives here literally (or empty). When it isn't a
  # real pane id, self-resolve to the session's active pane — which is the pane
  # that triggered the popup.
  case "$SRC_PANE" in
    %[0-9]*) ;;
    *) SRC_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null) ;;
  esac
  if [ "$(session_provider)" = "litellm" ]; then
    cost_main
  else
    usage_main
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ "${1:-}" = "--popup" ]; then
    popup_main "$2" "$3"
  else
    main "$@"
  fi
fi
