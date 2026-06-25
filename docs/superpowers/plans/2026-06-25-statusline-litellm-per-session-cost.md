# Statusline per-session LiteLLM cost — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each Claude Code session's real proxy-billed spend on the statusline `$` segment, sourced from the LiteLLM ledger (the same source of truth as `prefix + u`).

**Architecture:** The proxy tags every request with Claude Code's `x-claude-code-session-id` (via `extra_spend_tag_headers`). A sourceable helper (`statusline-cost.sh`) sums that session's `spend` from `GET /spend/logs`, behind a per-session cache refreshed by a throttled, detached background job. The statusline sources the helper and shows the cached number when the session is LiteLLM-routed.

**Tech Stack:** bash, `jq`, `curl`, LiteLLM proxy (OSS), chezmoi, Docker Compose.

## Global Constraints

- Target spec: `docs/superpowers/specs/2026-06-25-statusline-litellm-per-session-cost-design.md`.
- The statusline repaints constantly — it MUST NOT `curl` inline; it reads a cache and spawns a detached background refresh only.
- Read endpoint is OSS-only: `GET /spend/logs?start_date=…&end_date=…&summarize=false`. Do NOT use `/spend/tags` or `/global/spend/report` (enterprise).
- No changes to `cv` — Claude Code already sends `x-claude-code-session-id`.
- Bearer token = `ANTHROPIC_AUTH_TOKEN` from the env (already the master key in `cv` sessions). Base = `ANTHROPIC_BASE_URL`.
- macOS client: use BSD `date`/`stat` with GNU fallbacks (`date -v…`/`stat -f` then `date -d…`/`stat -c`).
- Cache file: `${TMPDIR:-/tmp}/claude-cc-cost.<session_id>`. TTL 30s; stale-lock break 60s.
- Per-session color bands: gray `<$3`, green `<$9`, yellow `<$18`, orange `<$30`, red `≥$30`.
- Tests are network-free bash and source files from the **source tree** (mirror `dot_tmux/scripts/tests/test-claude-cost.sh`).

---

### Task 1: Proxy tags requests with the session id

**Files:**
- Modify: `private_projects/private_gamuda/litellm-tracker/config.yaml` (append a top-level `litellm_settings` block)

**Interfaces:**
- Produces: spend-log entries whose `request_tags` array contains the value of `x-claude-code-session-id`. Task 2's `session_spend` filter depends on the exact stored shape, which this task confirms empirically (raw value vs `"x-claude-code-session-id: <value>"`).

- [ ] **Step 1: Add the config block**

Append to `private_projects/private_gamuda/litellm-tracker/config.yaml` (file currently ends after the `model_list:` entries):

```yaml

litellm_settings:
  extra_spend_tag_headers:
    - "x-claude-code-session-id"
```

- [ ] **Step 2: Commit the config change**

```bash
git add private_projects/private_gamuda/litellm-tracker/config.yaml
git commit -m "feat(litellm): tag spend logs with x-claude-code-session-id"
```

- [ ] **Step 3: Deploy + restart the proxy on onyx**

On onyx (or via `ssh onyx`):

```bash
chezmoi update                                   # pulls + applies config.yaml
cd ~/projects/gamuda/litellm-tracker && docker compose up -d   # reloads read-only config
```

Expected: the `litellm` container recreates; `curl -fsS http://localhost:4000/health/liveliness` returns OK.

- [ ] **Step 4: Verify tagging end-to-end and capture the tag shape**

From any tailnet host, run one request through the proxy, then read it back. Replace `<KEY>` with `$LITELLM_MASTER_KEY` and `<BASE>` with `http://onyx.tail5d740c.ts.net:4000` (or `http://localhost:4000` on onyx):

```bash
# fire one tagged request (mimics Claude Code's header)
curl -sS -X POST "<BASE>/v1/messages" \
  -H "Authorization: Bearer <KEY>" \
  -H "x-claude-code-session-id: PLAN-PROBE-001" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5@20251001","max_tokens":8,"messages":[{"role":"user","content":"hi"}]}' >/dev/null

sleep 5   # spend logs are written async

# read it back — inspect request_tags
TODAY=$(date -v-1d +%F 2>/dev/null || date -d 'yesterday' +%F)
TOM=$(date -v+1d +%F 2>/dev/null || date -d 'tomorrow' +%F)
curl -sS "<BASE>/spend/logs?start_date=$TODAY&end_date=$TOM&summarize=false" \
  -H "Authorization: Bearer <KEY>" \
  | jq '[.[] | {spend, request_tags}] | map(select(.request_tags | tostring | contains("PLAN-PROBE-001")))'
```

Expected: at least one entry whose `request_tags` includes `PLAN-PROBE-001` (or `x-claude-code-session-id: PLAN-PROBE-001`). **Record which shape appears** — it confirms Task 2's filter (the filter is written to match both, so either is fine, but note it in the Task 2 commit). If `request_tags` is empty, the config did not take effect; re-check Step 3.

---

### Task 2: `session_spend` pure function + tests

**Files:**
- Create: `dot_claude/statusline-cost.sh`
- Test: `dot_claude/tests/test-statusline-cost.sh`

**Interfaces:**
- Produces: `session_spend <logs_json> <session_id>` → USD total as jq's natural number string, rounded to 2dp (e.g. `0.42`, `0`); prints `0` on empty/invalid input or empty session id.

- [ ] **Step 1: Write the failing test**

Create `dot_claude/tests/test-statusline-cost.sh`:

```bash
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

exit $fail
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash dot_claude/tests/test-statusline-cost.sh`
Expected: FAIL — `statusline-cost.sh` does not exist / `session_spend: command not found`.

- [ ] **Step 3: Create the helper with `session_spend`**

Create `dot_claude/statusline-cost.sh`:

```bash
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
  printf '%s' "$logs" | jq -r --arg s "$sid" '
    [ .[]?
      | select((.request_tags // []) as $t
          | (($t | index($s)) != null)
            or any($t[]?; type == "string" and contains($s)))
      | (.spend // 0) ]
    | (add // 0) | (. * 100 | round) / 100' 2>/dev/null || printf '0'
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash dot_claude/tests/test-statusline-cost.sh`
Expected: all `ok` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add dot_claude/statusline-cost.sh dot_claude/tests/test-statusline-cost.sh
git commit -m "feat(statusline): session_spend pure ledger-summing function

request_tags shape confirmed in Task 1: <raw value | header: value>."
```

---

### Task 3: Cache read + throttled detached background refresh

**Files:**
- Modify: `dot_claude/statusline-cost.sh`
- Modify: `dot_claude/tests/test-statusline-cost.sh`

**Interfaces:**
- Consumes: `session_spend` (Task 2).
- Produces:
  - `_litellm_fetch_logs <base> <key> <start> <end>` → raw `/spend/logs` JSON (overridable in tests).
  - `_dir_age <path>` → integer seconds since mtime (empty on failure).
  - `_litellm_cost_refresh <base> <key> <session_id> <cache_file>` → fetch+sum+atomic-write, lock-guarded.
  - `litellm_session_cost <base> <key> <session_id>` → echoes the cached USD number (empty if none yet); spawns a detached refresh when cache missing/stale.

- [ ] **Step 1: Write the failing tests**

Append to `dot_claude/tests/test-statusline-cost.sh`, before the final `exit $fail`:

```bash
# --- cache + refresh -------------------------------------------------------
TMPDIR_T=$(mktemp -d)
CACHE="$TMPDIR_T/claude-cc-cost.sess-AAA"

# refresh writes the summed total for the session, via the (stubbed) fetch.
_litellm_fetch_logs() { printf '%s' "$LOGS"; }   # stub: return the fixture
_litellm_cost_refresh "http://x" "k" "sess-AAA" "$CACHE"
check "refresh writes summed cache" "0.42" "$(cat "$CACHE" 2>/dev/null)"
check "refresh clears its lock"     "0"    "$([ -d "$CACHE.lock" ]; echo $?)"

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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash dot_claude/tests/test-statusline-cost.sh`
Expected: FAIL — `_litellm_cost_refresh: command not found` (earlier `session_spend` tests still pass).

- [ ] **Step 3: Implement the cache + refresh functions**

Append to `dot_claude/statusline-cost.sh`:

```bash
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash dot_claude/tests/test-statusline-cost.sh`
Expected: all `ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add dot_claude/statusline-cost.sh dot_claude/tests/test-statusline-cost.sh
git commit -m "feat(statusline): per-session cost cache + throttled bg refresh"
```

---

### Task 4: Wire the ledger cost into the statusline

**Files:**
- Modify: `dot_claude/executable_statusline.sh` (source helper; three-way gating; cost override; recalibrate `color_for_cost`)
- Modify: `dot_claude/tests/test-statusline-cost.sh` (integration assertion)

**Interfaces:**
- Consumes: `litellm_session_cost` (Task 3); `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `.session_id`.

- [ ] **Step 1: Source the helper (self-relative)**

In `dot_claude/executable_statusline.sh`, immediately after `input=$(cat)` (line 4), add:

```bash

# LiteLLM per-session cost helper (sibling file; same dir in source tree and in
# ~/.claude when deployed).
source "$(dirname -- "${BASH_SOURCE[0]}")/statusline-cost.sh" 2>/dev/null || true
```

- [ ] **Step 2: Replace the cost gate with three-way detection**

Replace the current gate (lines 16-17):

```bash
show_cost="false"
{ [ -n "${CLAUDE_CODE_USE_VERTEX:-}" ] || [ -n "${ANTHROPIC_BASE_URL:-}" ]; } && show_cost="true"
```

with:

```bash
# Cost segment is three-way: LiteLLM-routed sessions show the proxy's real
# per-session spend (ledger); Vertex-direct sessions keep Claude Code's own
# estimate; everything else shows no cost.
litellm_routed="false"
[ -n "${ANTHROPIC_BASE_URL:-}" ] && litellm_routed="true"
show_cost="false"
{ [ "$litellm_routed" = "true" ] || [ -n "${CLAUDE_CODE_USE_VERTEX:-}" ]; } && show_cost="true"
```

- [ ] **Step 3: Stop emitting CC's estimate on the LiteLLM path**

In the `jq` call, pass the new flag and gate the CC cost field on the non-LiteLLM path. Change the `--arg show_cost "$show_cost"` line (line 22) to also pass `--arg litellm "$litellm_routed"`:

```bash
out=$(printf '%s' "$input" | jq -r --arg wt "$wt" --arg br "$br" --arg show_cost "$show_cost" --arg litellm "$litellm_routed" '
```

and change the cost field (line 26) from:

```bash
    (if $show_cost == "true" and (.cost.total_cost_usd != null) then (.cost.total_cost_usd | tostring) else "" end),
```

to:

```bash
    (if $show_cost == "true" and $litellm == "false" and (.cost.total_cost_usd != null) then (.cost.total_cost_usd | tostring) else "" end),
```

- [ ] **Step 4: Override `cost_raw` from the ledger on the LiteLLM path**

After the `IFS=$'\x01' read …` line (line 35), add:

```bash

# LiteLLM-routed: replace the (empty) estimate slot with this session's real
# ledger spend, read from the cache (refreshed in the background by the helper).
if [ "$litellm_routed" = "true" ]; then
  cost_raw=$(litellm_session_cost "${ANTHROPIC_BASE_URL:-}" "${ANTHROPIC_AUTH_TOKEN:-}" "$session_id")
fi
```

- [ ] **Step 5: Recalibrate `color_for_cost` for per-session magnitude**

Replace the `awk` thresholds inside `color_for_cost` (lines 109-115) with the per-session bands:

```bash
  tier=$(awk -v u="$1" 'BEGIN {
    if      (u <  3) print "gray"
    else if (u <  9) print "green"
    else if (u < 18) print "yellow"
    else if (u < 30) print "orange"
    else             print "red"
  }')
```

(The five `case` arms below it are unchanged — same colors, new boundaries.)

- [ ] **Step 6: Add the integration assertion**

Append to `dot_claude/tests/test-statusline-cost.sh`, before the final `exit $fail`:

```bash
# --- integration: statusline renders the ledger cost on the LiteLLM path ----
STATUS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/executable_statusline.sh"
TMPDIR_I=$(mktemp -d)
printf '1.23' > "$TMPDIR_I/claude-cc-cost.test-sess"     # fresh cache, no refresh
strip() { sed $'s/\033\\[[0-9;]*m//g'; }
render=$(printf '{"session_id":"test-sess","model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":10}}' \
  | TMPDIR="$TMPDIR_I" ANTHROPIC_BASE_URL="http://x" ANTHROPIC_AUTH_TOKEN="k" COLUMNS=200 \
    bash "$STATUS" | strip)
check "statusline shows ledger cost" "1" "$(printf '%s' "$render" | grep -c '\$1\.23')"
rm -rf "$TMPDIR_I"
```

- [ ] **Step 7: Run the full test suite**

Run: `bash dot_claude/tests/test-statusline-cost.sh`
Expected: all `ok` (session_spend + cache + integration), exit 0.

- [ ] **Step 8: Commit**

```bash
git add dot_claude/executable_statusline.sh dot_claude/tests/test-statusline-cost.sh
git commit -m "feat(statusline): show real per-session LiteLLM ledger cost"
```

---

### Task 5: Deploy + end-to-end verification

**Files:** none (deploy + manual verification)

- [ ] **Step 1: Apply the dotfiles**

```bash
chezmoi diff dot_claude/statusline.sh dot_claude/statusline-cost.sh   # review
chezmoi apply
```

Expected: `~/.claude/statusline.sh` and `~/.claude/statusline-cost.sh` updated; helper present (mode 0644).

- [ ] **Step 2: Smoke-test the deployed statusline**

```bash
printf '{"session_id":"smoke","model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":5}}' \
  | ANTHROPIC_BASE_URL="http://onyx.tail5d740c.ts.net:4000" ANTHROPIC_AUTH_TOKEN="$LITELLM_MASTER_KEY" COLUMNS=200 \
    bash ~/.claude/statusline.sh; echo
```

Expected: a status line renders without error (cost blank on first paint for an unused `smoke` session; a background refresh writes `${TMPDIR}/claude-cc-cost.smoke` ≈ `0` within a few seconds — confirm with `cat`).

- [ ] **Step 3: Real-session cross-check against `prefix + u`**

Start a `cv` session, issue a couple of prompts, wait ~10s for spend logs to land, then:
- Confirm the statusline `$` segment shows a non-zero figure that grows with use.
- Open `prefix + u` and confirm the statusline figure is consistent with that session's contribution to the ledger (it will be ≤ the all-time total; per-session, so smaller).

- [ ] **Step 4: Final commit / sync**

If `chezmoi apply` produced no further source changes, nothing to commit. Otherwise:

```bash
git add -A && git commit -m "chore(statusline): deploy per-session LiteLLM cost"
git push
```

---

## Self-Review

**Spec coverage:**
- Proxy `extra_spend_tag_headers` → Task 1. ✓
- Three-way gating → Task 4 Steps 2-3. ✓
- Cache + throttled detached refresh + stale-lock break → Task 3. ✓
- `/spend/logs` window ±1 day, bearer from env → Task 3 Step 3. ✓
- Display `$X.XX` + recalibrated bands (3/9/18/30) → Task 4 Step 5. ✓
- Blank-until-first-fetch, `$0.00` on confirmed zero → Task 3 (`litellm_session_cost` empty when no cache; `session_spend` returns `0`) + Task 4 (`cost_raw` empty ⇒ no segment). ✓
- Pure `session_spend` + network-free tests → Task 2. ✓
- Edge cases (unreachable, malformed, missing session id, stale lock) → Tasks 2-3 tests. ✓
- Manual cross-check vs `prefix + u` → Task 5 Step 3. ✓

**Placeholder scan:** none — every code/step is concrete; the only deferred item (exact `request_tags` shape) is resolved empirically in Task 1 and the filter matches both shapes.

**Type consistency:** `session_spend`, `_litellm_fetch_logs`, `_dir_age`, `_litellm_cost_refresh`, `litellm_session_cost` names are identical across definitions, tests, and the statusline call site. `litellm_routed`/`show_cost` flags are consistent across the gate, the jq args, and the override.

**Note (display zero):** `session_spend` returns `0` (not `0.00`); the statusline formats with `awk '$%.2f'`, so a confirmed-zero session shows `$0.00`. A never-yet-fetched session has no cache file ⇒ `cost_raw` empty ⇒ no `$` segment, matching the spec's "blank until first fetch".
