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

LITELLM_COST_TTL=30          # seconds: refresh when the cache is older than this
LITELLM_COST_LOCK_STALE=60   # seconds: break a lock left by a crashed refresh

# _dir_age <path> : seconds since the path's mtime (BSD stat, then GNU). Empty on
# failure (e.g. path missing).
_dir_age() {
  local m now
  m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || return 1
  now=$(date +%s)
  printf '%s' $(( now - m ))
}

# _litellm_fetch_logs <base> <key> <start> <end> : raw /spend/logs JSON for the
# window. Thin authenticated GET; overridden in tests. Empty on failure.
_litellm_fetch_logs() {
  curl -fsS -m 5 -H "Authorization: Bearer $2" \
    "$1/spend/logs?start_date=$3&end_date=$4&summarize=false" 2>/dev/null
}

# _litellm_cost_refresh <base> <key> <session_id> <cache_file> : fetch the recent
# window, sum this session's spend, write it atomically. Lock-guarded so rapid
# repaints collapse to one in-flight refresh; a stale lock is broken first. On an
# unreachable proxy the old cache is left untouched.
_litellm_cost_refresh() {
  local base=$1 key=$2 sid=$3 cache=$4 lock="$4.lock"
  if [ -d "$lock" ]; then
    local age; age=$(_dir_age "$lock")
    [ "${age:-0}" -gt "$LITELLM_COST_LOCK_STALE" ] && rmdir "$lock" 2>/dev/null
  fi
  mkdir "$lock" 2>/dev/null || return     # another refresh already in flight
  trap 'rmdir "'"$lock"'" 2>/dev/null' RETURN
  local start end logs total
  start=$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)
  end=$(date -v+1d +%F 2>/dev/null || date -d 'tomorrow' +%F)
  logs=$(_litellm_fetch_logs "$base" "$key" "$start" "$end")
  [ -n "$logs" ] || return                # unreachable -> keep the old cache
  total=$(session_spend "$logs" "$sid")
  printf '%s' "$total" > "$cache.tmp" && mv "$cache.tmp" "$cache"
}

# litellm_session_cost <base> <key> <session_id> : echo this session's cached
# spend (USD number, or nothing if never fetched). Spawns a DETACHED refresh when
# the cache is missing or older than the TTL — never blocks the statusline.
litellm_session_cost() {
  local base=$1 key=$2 sid=$3
  [ -n "$sid" ] || return
  local cache="${TMPDIR:-/tmp}/claude-cc-cost.$sid" need=1
  if [ -f "$cache" ]; then
    local age; age=$(_dir_age "$cache")
    [ "${age:-9999}" -le "$LITELLM_COST_TTL" ] && need=0
  fi
  if [ "$need" -eq 1 ]; then
    ( _litellm_cost_refresh "$base" "$key" "$sid" "$cache" >/dev/null 2>&1 & )
  fi
  [ -f "$cache" ] && cat "$cache"
}
