#!/usr/bin/env bash
# LiteLLM per-session cost helper for the Claude Code statusline.
# Sourced by ~/.claude/statusline.sh; never executed directly. All functions
# are pure or self-contained so the file is safe to source in tests.

# session_spend <logs_json> <session_id> : sum .spend across /spend/logs entries
# whose request_tags include <session_id>. Pure (no network). Prints the total
# rounded to 2dp as jq's natural number string, or "0" on empty/invalid input.
# Matches both a raw-value tag and a "x-claude-code-session-id: <value>" shape.
session_spend() {
  local logs=$1 sid=$2
  [ -n "$sid" ] || { printf '0'; return; }
  [ -n "$logs" ] || { printf '0'; return; }
  printf '%s' "$logs" | jq -r --arg s "$sid" '
    [ .[]?
      | select((.request_tags // []) as $t
          | any($t[]?; type == "string" and (. == $s or endswith(": " + $s))))
      | (.spend // 0) ]
    | (add // 0) | (. * 100 | round) / 100' 2>/dev/null || printf '0'
}
