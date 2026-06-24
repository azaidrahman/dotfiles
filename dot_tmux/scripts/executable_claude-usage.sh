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

# Vertex per-1M-token pricing (USD). Family-substring matched; flat (no long-context tier).
# cache-write = 5-minute rate (1.25x input); accepted approximation.
COST_PRICE_JSON='{
  "opus":  {"in":5, "out":25,"cw":6.25,"cr":0.5},
  "sonnet":{"in":3, "out":15,"cw":3.75,"cr":0.3},
  "haiku": {"in":1, "out":5, "cw":1.25,"cr":0.1},
  "fable": {"in":10,"out":50,"cw":12.5,"cr":1.0}
}'

# cost_compute <cutoff_epoch> <file>... : sum spend by token type. cutoff 0 = no time filter.
cost_compute() {
  local cutoff=$1; shift
  [ "$#" -eq 0 ] && { printf 'input 0\noutput 0\ncache_write 0\ncache_read 0\ntotal 0\nother_tokens 0\nother_models \n'; return; }
  cat "$@" 2>/dev/null | jq -nrR --argjson cutoff "$cutoff" --argjson price "$COST_PRICE_JSON" '
    def family($m): ($m // "") | ascii_downcase as $l
      | if   ($l|test("opus"))   then "opus"
        elif ($l|test("sonnet")) then "sonnet"
        elif ($l|test("haiku"))  then "haiku"
        elif ($l|test("fable"))  then "fable"
        else "other" end;
    def epoch($t): ($t // "") | sub("\\.[0-9]+Z$";"Z") | (try fromdateiso8601 catch 0);
    reduce (inputs | (fromjson? // empty)) as $e
      ({input:0,output:0,cw:0,cr:0,other_tok:0,others:{}};
        if ($e.type=="assistant") and ($e.message.usage != null)
           and (epoch($e.timestamp) >= $cutoff)
        then
          family($e.message.model) as $f
          | $e.message.usage as $u
          | (($u.input_tokens // 0)) as $it
          | (($u.output_tokens // 0)) as $ot
          | (($u.cache_creation_input_tokens // 0)) as $ct
          | (($u.cache_read_input_tokens // 0)) as $rt
          | if $f=="other"
            then .other_tok += ($it+$ot+$ct+$rt) | .others[($e.message.model // "unknown")] = true
            else $price[$f] as $p
              | .input  += $it*$p.in/1000000
              | .output += $ot*$p.out/1000000
              | .cw     += $ct*$p.cw/1000000
              | .cr     += $rt*$p.cr/1000000
            end
        else . end)
    | .total = (.input + .output + .cw + .cr)
    | "input \(.input)\noutput \(.output)\ncache_write \(.cw)\ncache_read \(.cr)\ntotal \(.total)\nother_tokens \(.other_tok)\nother_models \((.others|keys|join(",")))"
  '
}

# render_cost <compute_output> : draw the 7-day cost breakdown.
render_cost() {
  local data=$1 v
  v() { printf '%s\n' "$data" | grep "^$1 " | cut -d' ' -f2-; }
  local in=$(v input) out=$(v output) cw=$(v cache_write) cr=$(v cache_read)
  local total=$(v total) other=$(v other_tokens) models=$(v other_models)

  clear 2>/dev/null
  echo
  printf '  %sCost · last 7 days%s\n\n' "$c_bold" "$c_reset"

  # zero spend with no untracked models → fallback
  if awk -v t="${total:-0}" -v o="${other:-0}" 'BEGIN{exit !((t+0==0) && (o+0==0))}'; then
    printf '  %sno spend in the last 7 days%s\n' "$c_dim" "$c_reset"
    return
  fi

  # if total is 0 but other tokens exist, just show the flag and return
  if awk -v t="${total:-0}" 'BEGIN{exit !(t+0==0)}'; then
    if [ "${other:-0}" -gt 0 ] 2>/dev/null && [ "$other" != "0" ]; then
      printf '  %s+ untracked model(s): %s — add to pricing table%s\n' "$c_dim" "$models" "$c_reset"
    fi
    return
  fi

  local max; max=$(awk -v a="$in" -v b="$out" -v c="$cw" -v d="$cr" \
    'BEGIN{m=a;if(b>m)m=b;if(c>m)m=c;if(d>m)m=d; if(m<=0)m=1; print m}')
  local width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
  local bar_w=$(( width - 34 )); (( bar_w < 8 )) && bar_w=8; (( bar_w > 32 )) && bar_w=32

  costbar() { # label value
    local label=$1 val=$2 fill empty pct
    pct=$(awk -v v="$val" -v m="$max" 'BEGIN{printf "%d", (v/m)*100}')
    fill=$(( pct * bar_w / 100 )); (( fill < 0 )) && fill=0; (( fill > bar_w )) && fill=bar_w
    empty=$(( bar_w - fill ))
    printf '  %-12s %s%s%s%s%s %s$%0.2f%s\n' \
      "$label" "$(color_for "$pct")" "$(repeat █ "$fill")" "$c_dim" "$(repeat ░ "$empty")" \
      "$c_reset" "$c_bold" "$val" "$c_reset"
  }
  costbar "Input"       "$in"
  costbar "Output"      "$out"
  costbar "Cache write" "$cw"
  costbar "Cache read"  "$cr"
  printf '  %s%s%s\n' "$c_dim" "$(repeat ─ $(( bar_w + 12 )))" "$c_reset"
  printf '  %-12s %*s%s$%0.2f%s\n' "Total" "$bar_w" "" "$c_bold" "$total" "$c_reset"

  if [ "${other:-0}" -gt 0 ] 2>/dev/null && [ "$other" != "0" ]; then
    printf '\n  %s+ untracked model(s): %s — add to pricing table%s\n' "$c_dim" "$models" "$c_reset"
  fi
}

COST_CACHE="${TMPDIR:-/tmp}/claude-cost.cache"

cost_main() {
  # instant draw from cache (computed compute-output is what we cache)
  if [[ -s $COST_CACHE ]]; then
    render_cost "$(cat "$COST_CACHE")"
    printf '\n  %s(cached — refreshing…)%s\n' "$c_dim" "$c_reset"
  else
    clear 2>/dev/null
    echo
    printf '  %sCost · last 7 days%s\n\n  %sLoading…%s\n' "$c_bold" "$c_reset" "$c_dim" "$c_reset"
  fi

  # fresh compute over last-7-day transcripts
  local cutoff; cutoff=$(( $(date +%s) - 7*86400 ))
  local files=()
  while IFS= read -r f; do files+=("$f"); done < <(find "$HOME/.claude/projects" -name '*.jsonl' -mtime -7 2>/dev/null)
  local fresh; fresh=$(cost_compute "$cutoff" "${files[@]}")
  printf '%s\n' "$fresh" > "$COST_CACHE"
  render_cost "$fresh"

  echo
  printf '  %s[any key to close]%s' "$c_dim" "$c_reset"
  local old_stty; old_stty=$(stty -g 2>/dev/null)
  stty -echo -icanon min 1 time 0 2>/dev/null
  dd bs=1 count=1 >/dev/null 2>&1
  [ -n "$old_stty" ] && stty "$old_stty" 2>/dev/null
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

main() {
  if [ -n "${CLAUDE_CODE_USE_VERTEX:-}" ]; then
    cost_main
  else
    usage_main
  fi
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
