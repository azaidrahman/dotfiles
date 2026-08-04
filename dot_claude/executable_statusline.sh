#!/usr/bin/env bash
# Claude Code status line: [vim mode] | model | effort | ctx | rate limits   …   worktree | branch
# (worktree/branch are right-aligned to the terminal edge)
input=$(cat)

# LiteLLM per-session cost helper (sibling file; same dir in source tree and in
# ~/.claude when deployed).
source "$(dirname -- "${BASH_SOURCE[0]}")/statusline-cost.sh" 2>/dev/null || true

dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$dir" ] && dir="$PWD"

wt=""
br=""
if gitinfo=$(git -C "$dir" rev-parse --show-toplevel --abbrev-ref HEAD 2>/dev/null); then
  wt=$(basename "$(printf '%s' "$gitinfo" | sed -n 1p)")
  br=$(printf '%s' "$gitinfo" | sed -n 2p)
fi

# Cost segment: only LiteLLM-routed sessions (cv) show the proxy's real
# per-session spend (ledger), overwritten below. Everything else shows no cost.
litellm_routed="false"
[ -n "${ANTHROPIC_BASE_URL:-}" ] && litellm_routed="true"
show_cost="false"

# jq pass: emit fields joined by \x01 (non-whitespace) so IFS read preserves empty fields.
# Tab (\t) collapses consecutive delimiters in bash IFS read; \x01 does not.
mode=$(printf '%s' "$input" | jq -r '.vim.mode // ""')
out=$(printf '%s' "$input" | jq -r --arg wt "$wt" --arg br "$br" --arg show_cost "$show_cost" --arg litellm "$litellm_routed" '
  [
    (.model.display_name // ""),
    (.effort.level // ""),
    (if $show_cost == "true" and $litellm == "false" and (.cost.total_cost_usd != null) then (.cost.total_cost_usd | tostring) else "" end),
    ((.context_window.used_percentage // 0) | tostring),
    $wt,
    $br,
    (if .rate_limits.five_hour then (.rate_limits.five_hour.used_percentage | round | tostring) else "" end),
    (if .rate_limits.seven_day then (.rate_limits.seven_day.used_percentage | round | tostring) else "" end),
    (.session_id // "")
  ] | join("")')

IFS=$'\x01' read -r model effort cost_raw ctx_pct wt br five_h_pct seven_d_pct session_id <<< "$out"

# LiteLLM-routed: replace the (empty) estimate slot with this session's real
# ledger spend, read from the cache (refreshed in the background by the helper).
if [ "$litellm_routed" = "true" ]; then
  cost_raw=$(litellm_session_cost "${ANTHROPIC_BASE_URL:-}" "${ANTHROPIC_AUTH_TOKEN:-}" "$session_id")
fi

# ── Color helpers (256-color for tmux stability) ───────────────────────────────

reset=$'\033[0m'
gray=$'\033[38;5;244m'   # dim — for low-signal labels (session id, etc.)

# Shared green→red ramp (256-color, coolest→hottest = cheapest/lowest → priciest/highest).
PALETTE=(82 226 208 196)   # green  yellow  orange  red
GRAY=244                   # unknown / not-worth-highlighting

# rank_color <value> <rank…>: place <value> on PALETTE by its position in the
# ordered rank list. Each rank arg is a glob (|-separated synonyms ok). The index
# is bucketed onto the palette via floor(idx * |PALETTE| / count), so the same
# ramp stretches over however many ranks exist — append a new model/effort in
# cost order and every color auto-rebalances; no SGR code is ever chosen by hand.
# Unmatched values fall through to GRAY.
rank_color() {
  local lc; lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]'); shift
  local ranks=("$@") n=$# i pats pat
  for i in "${!ranks[@]}"; do
    IFS='|' read -ra pats <<< "${ranks[$i]}"   # split synonyms; |-in-case-pattern doesn't alternate from a var
    for pat in "${pats[@]}"; do
      if [[ $lc == $pat ]]; then               # unquoted RHS globs but, inside [[ ]], won't pathname-expand
        printf '\033[38;5;%sm' "${PALETTE[$(( i * ${#PALETTE[@]} / n ))]}"
        return
      fi
    done
  done
  printf '\033[38;5;%sm' "$GRAY"
}

# Ordered cheap/low → pricey/high. Models match on family substring, so new
# *versions* (e.g. a future "sonnet 5") already slot in; only a brand-new family
# needs a one-token insert here.
MODEL_RANK=('*haiku*' '*sonnet*' '*opus*' '*fable*')
EFFORT_RANK=('low|minimal' 'medium|normal' 'high' 'xhigh' 'ultra|max|highest')

color_for_model()  { rank_color "$1" "${MODEL_RANK[@]}"; }
color_for_effort() { rank_color "$1" "${EFFORT_RANK[@]}"; }

# Short model label: family initial + version, dropping any "(1M context)" suffix.
# e.g. "Sonnet 4.6" → "S4.6", "Opus 4.8 (1M context)" → "O4.8". Color still comes
# from the full name, so the rank logic above is untouched. Unknown family → as-is.
model_short() {
  local lc letter ver
  lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    *haiku*)  letter=H ;;
    *sonnet*) letter=S ;;
    *opus*)   letter=O ;;
    *fable*)  letter=F ;;
    *)        printf '%s' "$1"; return ;;
  esac
  ver=$(printf '%s' "$1" | grep -oE '[0-9]+(\.[0-9]+)?' | head -n1)
  printf '%s%s' "$letter" "$ver"
}

# rate_glyph <letter> <pct>: a single colored letter once usage clears 40% —
# yellow 40–70, orange 70–90, red >90. Below 40% it's noise, so emit nothing.
rate_glyph() {
  local letter=$1 pct=$2 col
  [ -z "$pct" ] && return
  if   [ "$pct" -le 40 ]; then return                   # hidden — not worth a glyph yet
  elif [ "$pct" -le 70 ]; then col='\033[38;5;226m'     # yellow
  elif [ "$pct" -le 90 ]; then col='\033[38;5;208m'     # orange
  else                         col='\033[38;5;196m'     # red
  fi
  printf '%b%s%b' "$col" "$letter" "$reset"
}

# color_for_ctx <pct>: gray below 30%, green→red from 30% to 85%+
color_for_ctx() {
  local tier
  tier=$(awk -v p="$1" 'BEGIN {
    if      (p < 30) print "gray"
    else if (p < 50) print "green"
    else if (p < 70) print "yellow"
    else if (p < 85) print "orange"
    else             print "red"
  }')
  case "$tier" in
    gray)   printf '\033[38;5;244m' ;;
    green)  printf '\033[38;5;82m'  ;;
    yellow) printf '\033[38;5;226m' ;;
    orange) printf '\033[38;5;208m' ;;
    red)    printf '\033[38;5;196m' ;;
  esac
}

# color_for_cost <usd>: gray below $20, green→red from $20 to $100+
color_for_cost() {
  local tier
  tier=$(awk -v u="$1" 'BEGIN {
    if      (u <  3) print "gray"
    else if (u <  9) print "green"
    else if (u < 18) print "yellow"
    else if (u < 30) print "orange"
    else             print "red"
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

sep=" | "
segments=()        # left side
right_segments=()  # right-aligned: worktree / branch

[ -n "$model"  ] && segments+=("$(color_for_model  "$model")$(model_short "$model")${reset}")
[ -n "$effort" ] && segments+=("$(color_for_effort "$effort")${effort}${reset}")

if [ -n "$cost_raw" ]; then
  cost_display=$(awk -v u="$cost_raw" 'BEGIN { printf "$%.2f", u+0 }')
  segments+=("$(color_for_cost "$cost_raw")${cost_display}${reset}")
fi

# Rate-limit glyphs, right before ctx: S = session (5h), W = weekly (7d). Each
# letter appears (colored by severity) only once its limit clears 40%; otherwise
# it's omitted. So this segment is "SW", "W", "S", or absent — e.g. "SW | ctx:50%".
glyphs="$(rate_glyph S "$five_h_pct")$(rate_glyph W "$seven_d_pct")"
[ -n "$glyphs" ] && segments+=("$glyphs")

segments+=("$(color_for_ctx "$ctx_pct")ctx:${ctx_pct}%${reset}")

# Session ID, last 5 chars — enough to disambiguate panes without the clutter.
[ -n "$session_id" ] && segments+=("${gray}id:${session_id: -5}${reset}")

[ -n "$wt" ] && right_segments+=("wt:${wt}")
[ -n "$br" ] && right_segments+=("br:${br}")

# ── Assemble ───────────────────────────────────────────────────────────────────

# join <sep> <elements…> → joined string
join_segs() {
  local s=$1; shift
  local out="" i
  for i in "$@"; do
    [ -z "$out" ] && out="$i" || out="${out}${s}${i}"
  done
  printf '%s' "$out"
}

result=$(join_segs "$sep" "${segments[@]}")

# Vim-mode indicator: blue for INSERT, gray otherwise. Shown as a single letter
# (I / N / V …) rather than the full word.
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
  left=$(printf '%s%s\033[0m | %s' "$color" "${mode:0:1}" "$result")
else
  left="$result"
fi

right=$(join_segs "$sep" "${right_segments[@]}")

# Right-align worktree/branch to the terminal edge. Claude Code exports COLUMNS
# before running this script (tput cols does NOT work here — output is captured,
# not attached to a tty). Visible width ignores ANSI SGR codes. If both sides
# can't share one line, append inline instead so the status never wraps to a
# second row (a wrapped status flickers — same reason we avoid a trailing \n).
visible_len() {
  local s; s=$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g')
  printf '%s' "${#s}"
}

RMARGIN=6   # columns kept blank at the right edge. Must cover Claude Code's built-in
            # status indent + a wrap-safety column, else the branch truncates. Bump higher
            # if the rightmost text still gets cut; lower it to sit closer to the edge.

if [ -n "$right" ] && [ "${COLUMNS:-0}" -gt 0 ]; then
  pad=$(( COLUMNS - RMARGIN - $(visible_len "$left") - $(visible_len "$right") ))
  if [ "$pad" -ge 1 ]; then
    printf '%s%*s%s' "$left" "$pad" "" "$right"
  else
    printf '%s%s%s' "$left" "$sep" "$right"   # too narrow to right-align; keep inline
  fi
elif [ -n "$right" ]; then
  printf '%s%s%s' "$left" "$sep" "$right"
else
  printf '%s' "$left"
fi
