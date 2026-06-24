#!/usr/bin/env bash
# Unit tests for the Vertex cost path in claude-usage.sh
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

source "$SCRIPT" 2>/dev/null   # bring cost_compute into scope

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 1M tokens of each type on opus → in 5, out 25, cw 6.25, cr 0.50
cat > "$TMP/opus.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-06-24T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":1000000,"output_tokens":1000000,"cache_creation_input_tokens":1000000,"cache_read_input_tokens":1000000}}}
EOF

get() { grep "^$1 " | awk '{print $2}'; }
res=$(cost_compute 0 "$TMP/opus.jsonl")
check "opus input cost"       "5"    "$(printf '%s\n' "$res" | get input)"
check "opus output cost"      "25"   "$(printf '%s\n' "$res" | get output)"
check "opus cache_write cost" "6.25" "$(printf '%s\n' "$res" | get cache_write)"
check "opus cache_read cost"  "0.5"  "$(printf '%s\n' "$res" | get cache_read)"
check "opus total cost"       "36.75" "$(printf '%s\n' "$res" | get total)"

# Unknown model → counted as other, zero priced
cat > "$TMP/other.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-06-24T10:00:00.000Z","message":{"model":"claude-zzz-9","usage":{"input_tokens":500,"output_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
EOF
res=$(cost_compute 0 "$TMP/other.jsonl")
check "other tokens summed"   "1000"        "$(printf '%s\n' "$res" | get other_tokens)"
check "other models listed"   "claude-zzz-9" "$(printf '%s\n' "$res" | get other_models)"
check "other total is zero"   "0"           "$(printf '%s\n' "$res" | get total)"

# Time filter: an old line excluded when cutoff is after it
cat > "$TMP/old.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2020-01-01T00:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
EOF
res=$(cost_compute 1700000000 "$TMP/old.jsonl")   # cutoff in 2023, line is 2020
check "old line excluded by cutoff" "0" "$(printf '%s\n' "$res" | get total)"

# Malformed line is skipped, valid line still counts
printf 'not json\n' > "$TMP/bad.jsonl"
cat "$TMP/opus.jsonl" >> "$TMP/bad.jsonl"
res=$(cost_compute 0 "$TMP/bad.jsonl")
check "malformed line skipped" "36.75" "$(printf '%s\n' "$res" | get total)"

exit $fail
