#!/usr/bin/env bash
# Unit tests for the LiteLLM per-session cost helper (statusline-cost.sh).
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/statusline-cost.sh"
fail=0
check() { # label expected actual
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"
  else printf 'FAIL - %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}

# Sourcing must be side-effect free (defines functions, prints nothing).
out=$( source "$LIB" 2>/dev/null; echo "SOURCED_OK" )
check "source is side-effect free" "SOURCED_OK" "${out##*$'\n'}"

source "$LIB" 2>/dev/null

# --- session_spend: sum .spend over entries whose request_tags ⊇ session ----
LOGS='[
 {"spend":0.10,"request_tags":["sess-AAA"]},
 {"spend":0.32,"request_tags":["sess-AAA","model-opus"]},
 {"spend":0.99,"request_tags":["sess-BBB"]},
 {"spend":0.05,"request_tags":[]}
]'
check "sums only the matching session"      "0.42" "$(session_spend "$LOGS" "sess-AAA")"
check "non-matching session -> 0"           "0"    "$(session_spend "$LOGS" "sess-ZZZ")"
check "header:value tag shape also matches" "0.07" \
  "$(session_spend '[{"spend":0.07,"request_tags":["x-claude-code-session-id: sess-CCC"]}]' "sess-CCC")"
check "empty json -> 0"                      "0"    "$(session_spend "" "sess-AAA")"
check "malformed json -> 0"                  "0"    "$(session_spend "not json" "sess-AAA")"
check "missing session id -> 0"             "0"    "$(session_spend "$LOGS" "")"
check "prefix collision does not over-match" "0" \
  "$(session_spend '[{"spend":0.10,"request_tags":["x-claude-code-session-id: sess-AAA"]}]' "sess-A")"

exit $fail
