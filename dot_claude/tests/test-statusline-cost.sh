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

# --- cache + refresh -------------------------------------------------------
TMPDIR_T=$(mktemp -d)
CACHE="$TMPDIR_T/claude-cc-cost.sess-AAA"

# refresh writes the summed total for the session, via the (stubbed) fetch.
_litellm_fetch_logs() { printf '%s' "$LOGS"; }   # stub: return the fixture
_litellm_cost_refresh "http://x" "k" "sess-AAA" "$CACHE"
check "refresh writes summed cache" "0.42" "$(cat "$CACHE" 2>/dev/null)"
check "refresh clears its lock"     "1"    "$([ -d "$CACHE.lock" ]; echo $?)"

# a held lock blocks a concurrent refresh (no overwrite).
printf '5.55' > "$CACHE"; mkdir "$CACHE.lock"
_litellm_cost_refresh "http://x" "k" "sess-AAA" "$CACHE"
check "held lock blocks refresh" "5.55" "$(cat "$CACHE")"
rmdir "$CACHE.lock"

# a stale lock (older than 60s) is broken, refresh proceeds.
printf '5.55' > "$CACHE"; mkdir "$CACHE.lock"
touch -t "$(date -v-2M +%Y%m%d%H%M 2>/dev/null || date -d '2 minutes ago' +%Y%m%d%H%M)" "$CACHE.lock"
_litellm_cost_refresh "http://x" "k" "sess-AAA" "$CACHE"
check "stale lock broken, refresh runs" "0.42" "$(cat "$CACHE")"

# unreachable proxy (empty fetch) leaves the old cache untouched.
_litellm_fetch_logs() { printf ''; }
printf '7.77' > "$CACHE"
_litellm_cost_refresh "http://x" "k" "sess-AAA" "$CACHE"
check "empty fetch keeps old cache" "7.77" "$(cat "$CACHE")"

# litellm_session_cost echoes a fresh cache and does NOT refresh.
_litellm_fetch_logs() { printf '%s' "$LOGS"; }   # would write 0.42 if it ran
printf '1.23' > "$CACHE"
check "fresh cache echoed as-is" "1.23" \
  "$(TMPDIR="$TMPDIR_T" litellm_session_cost http://x k sess-AAA)"

# missing cache -> empty output (blank until first refresh lands).
rm -f "$CACHE"
check "missing cache -> empty" "" \
  "$(TMPDIR="$TMPDIR_T" litellm_session_cost http://x k sess-AAA 2>/dev/null; true)"
rm -rf "$TMPDIR_T"

exit $fail
