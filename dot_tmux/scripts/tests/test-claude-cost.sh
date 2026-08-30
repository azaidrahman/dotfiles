#!/usr/bin/env bash
# Unit tests for the LiteLLM-ledger cost path in claude-usage.sh
set -u
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/executable_claude-usage.sh"
fail=0
check() { # label expected actual
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"
  else printf 'FAIL - %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}

# Sourcing the script must NOT run the popup (no stdout, exit 0).
out=$( source "$SCRIPT" 2>/dev/null; echo "SOURCED_OK" )
check "source is side-effect free" "SOURCED_OK" "${out##*$'\n'}"

source "$SCRIPT" 2>/dev/null   # bring litellm_blob / render_cost into scope
PROVIDER=litellm               # render_cost asks the provider for its header

# --- litellm_blob: fold the proxy ledger JSON into a canonical blob ----------
MODELS='[{"model":"vertex_ai/claude-opus-4-8","total_spend":0.887},
         {"model":"vertex_ai/claude-sonnet-4-6","total_spend":0.359},
         {"model":"vertex_ai/claude-haiku-4-5","total_spend":0},
         {"model":"vertex_ai/gemini-3.1-pro","total_spend":1.40}]'
SPEND='{"spend":2.876,"max_budget":0.0}'
LOGS='[{"date":"2026-06-10","spend":5.0},
       {"date":"2026-06-20","spend":1.0},
       {"date":"2026-06-24","spend":0.5}]'

# cutoffs: 7d=2026-06-17, MTD=2026-06-01, YTD=2026-01-01, today=2026-06-24
blob=$(litellm_blob "$MODELS" "$SPEND" "$LOGS" "2026-06-17" "2026-06-01" "2026-01-01" "2026-06-24")
# TOTAL <key> <usd>, one record per line, tab separated.
get() { printf '%s\n' "$blob" | awk -F'\t' -v k="$1" '$1=="TOTAL" && $2==k {print $3; exit}'; }

check "all-time total from /global/spend" "2.876" "$(get all)"
check "7-day total sums on/after cutoff"  "1.5"   "$(get 7d)"
check "MTD total sums on/after 1st of month" "6.5" "$(get mtd)"
check "YTD total sums on/after 1st of year"  "6.5" "$(get ytd)"
check "today total sums on/after today cutoff" "0.5" "$(get today)"
check "models sorted by spend desc, prefix stripped" "gemini-3.1-pro" \
  "$(printf '%s\n' "$blob" | awk -F'\t' '$1=="MODEL"{print $3; exit}')"
check "zero-spend model dropped (3 of 4 kept)" "3" \
  "$(printf '%s\n' "$blob" | grep -c "^MODEL$(printf '\t')")"

# Empty / missing JSON degrades to zeros, no models.
blob0=$(litellm_blob "" "" "" "2026-06-17" "2026-06-01" "2026-01-01")
get0() { printf '%s\n' "$blob0" | awk -F'\t' -v k="$1" '$1=="TOTAL" && $2==k {print $3; exit}'; }
check "empty spend -> 0 all-time" "0" "$(get0 all)"
check "empty spend -> 0 7-day"    "0" "$(get0 7d)"
check "empty spend -> 0 MTD"      "0" "$(get0 mtd)"
check "empty spend -> 0 YTD"      "0" "$(get0 ytd)"
check "empty spend -> 0 today"    "0" "$(get0 today)"
check "empty -> no MODEL lines"   "0" "$(printf '%s\n' "$blob0" | grep -c "^MODEL$(printf '\t')")"

# --- render_cost: draw the blob --------------------------------------------
strip() { sed $'s/\033\\[[0-9;]*m//g'; }
out=$(SRC_PANE="" render_cost "$blob" "" | strip)
check "render shows a model + dollars" "1" "$(printf '%s\n' "$out" | grep -c 'gemini-3.1-pro .* \$1\.40')"
check "render shows 7-day total"       "1" "$(printf '%s\n' "$out" | grep -c 'last 7 days .* \$1\.50')"
check "render shows month-to-date total" "1" "$(printf '%s\n' "$out" | grep -c 'month to date .* \$6\.50')"
check "render shows year-to-date total"  "1" "$(printf '%s\n' "$out" | grep -c 'year to date .* \$6\.50')"
check "render shows all-time total"    "1" "$(printf '%s\n' "$out" | grep -c 'all-time .* \$2\.88')"
check "render shows today total"         "1" "$(printf '%s\n' "$out" | grep -c 'Today .* \$0\.50')"
check "render shows model share percent" "1" "$(printf '%s\n' "$out" | grep -c 'gemini-3.1-pro .* (52%)')"

out=$(SRC_PANE="" render_cost "$blob0" "" | strip)
check "render empty-ledger fallback" "1" "$(printf '%s\n' "$out" | grep -c 'no spend recorded')"

# A provider that could not reach its source speaks through a NOTE record.
out=$(SRC_PANE="" render_cost "NOTE$(printf '\t')proxy unreachable — could not fetch spend" "" | strip)
check "render shows a NOTE from the provider" "1" \
  "$(printf '%s\n' "$out" | grep -c 'proxy unreachable')"
check "a NOTE replaces the empty-ledger line" "0" \
  "$(printf '%s\n' "$out" | grep -c 'no spend recorded')"

# --- active session metrics ---------------------------------------------------
sess_record="SESSION$(printf '\t')gemini-3.7-flash$(printf '\t')50000$(printf '\t')1000000$(printf '\t')100000$(printf '\t')400000$(printf '\t')5000$(printf '\t')2000"
out_sess=$(SRC_PANE="" render_cost "$sess_record"$'\n'"$blob" "" | strip)
check "render shows active session header" "1" \
  "$(printf '%s\n' "$out_sess" | grep -c 'Active session · gemini-3.7-flash')"
check "render shows context window" "1" \
  "$(printf '%s\n' "$out_sess" | grep -c 'Context .* 50k / 1M (5%)')"
check "render shows cache hit percentage" "1" \
  "$(printf '%s\n' "$out_sess" | grep -c '80% hit')"
check "render shows thinking tokens" "1" \
  "$(printf '%s\n' "$out_sess" | grep -c '2k think')"

# --- fmt_tokens unit checks ---------------------------------------------------
check "fmt_tokens under 1k"    "500"   "$(fmt_tokens 500)"
check "fmt_tokens exact 1k"    "1k"    "$(fmt_tokens 1000)"
check "fmt_tokens fractional k" "50.5k" "$(fmt_tokens 50500)"
check "fmt_tokens exact 1M"    "1M"    "$(fmt_tokens 1000000)"
check "fmt_tokens fractional M" "1.05M" "$(fmt_tokens 1048576)"

exit $fail
