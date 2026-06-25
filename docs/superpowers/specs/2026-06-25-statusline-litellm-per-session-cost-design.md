# Per-session LiteLLM ledger cost on the Claude Code statusline

**Date:** 2026-06-25
**Status:** Implemented (branch `feat/statusline-litellm-cost`)

> **Revision (2026-06-25, post-deploy):** the read path changed from `/spend/logs`
> to `/tag/daily/activity?tags=<tag>`. Deploying on onyx revealed that
> `/spend/logs` has no server-side tag filter and returns the *entire* proxy log
> for the date window (~69 MB / 27k entries on a busy day) — it would time out
> over Tailscale from the client. `/tag/daily/activity` filters server-side by
> the `x-claude-code-session-id: <id>` tag and returns a small per-tag aggregate
> (`~3 KB`); the client reads `.metadata.total_spend`. The pure function is now
> `tag_total_spend <activity_json>` instead of `session_spend <logs_json> <sid>`.
> Sections below referencing `/spend/logs`/`session_spend` reflect the original
> design; the shipped code uses the tag endpoint.

## Problem

The statusline `$` segment (`dot_claude/executable_statusline.sh`) shows Claude
Code's own `cost.total_cost_usd`. For `cv` sessions routed through the LiteLLM
proxy, that number is an **estimate at Anthropic list rates**, not what the proxy
actually billed (Vertex pricing). We want the statusline to show the **real
per-session cost from the proxy's ledger** — the same source of truth the
`prefix + u` popup uses (`dot_tmux/scripts/executable_claude-usage.sh`).

This reverses an explicit non-goal in
`2026-06-24-litellm-cost-popup-design.md` ("Touching the statusline `$` segment …
Correct as-is"). That note assumed Claude Code's reported cost was good enough;
it is not for proxy-routed sessions. **This spec supersedes that non-goal.**

## Goal

When a session is routed through LiteLLM, the statusline `$` segment shows that
**session's** real spend as logged by the proxy. Non-proxy sessions are
unchanged.

## Non-goals

- Per-model breakdown on the statusline (that's what `prefix + u` is for).
- Changing `cv` — Claude Code already sends the per-session header (below).
- Account-wide / 7-day / all-time totals on the statusline (per-session only).
- Sub-second freshness — the figure lags the live session by seconds because the
  proxy writes spend logs asynchronously. Acceptable, and consistent with
  `prefix + u`.

## Key facts (verified)

- **Send side needs no changes.** Claude Code sends `x-claude-code-session-id` on
  every request — a per-session id documented "to aggregate all requests from one
  session without parsing request bodies"
  (https://code.claude.com/docs/en/llm-gateway-protocol.md). `cv` already sets
  `ANTHROPIC_BASE_URL` (proxy) and `ANTHROPIC_AUTH_TOKEN` (= `LITELLM_MASTER_KEY`).
  `statusline.sh` runs as a child of the `claude` process, so it reads both
  directly from the environment.
- **Proxy attribution is native.** `litellm_settings.extra_spend_tag_headers`
  turns a named request header into a spend tag recorded in
  `LiteLLM_SpendLogs.request_tags`
  (https://docs.litellm.ai/docs/proxy/cost_tracking,
  https://docs.litellm.ai/docs/proxy/request_tags).
- **Read endpoint is OSS-safe.** `GET /spend/logs?start_date=…&end_date=…&summarize=false`
  returns per-request entries including `spend` and `request_tags`
  (https://docs.litellm.ai/docs/proxy/cost_tracking). `/spend/tags` and
  `/global/spend/report?group_by=tags` appear under *enterprise* docs and are NOT
  relied upon.

## Data flow

```
cv → claude (ANTHROPIC_BASE_URL=onyx proxy; sends x-claude-code-session-id)
        │
        ▼
   LiteLLM proxy ──(extra_spend_tag_headers)──► SpendLogs.request_tags = [session-id]
        ▲                                                    │
        │ GET /spend/logs (background, throttled ~30s)       │
   statusline.sh ──filter tags⊇session, sum spend──► cache file ──► "$0.42" segment
```

## Component 1 — proxy config

`private_projects/private_gamuda/litellm-tracker/config.yaml` currently has only
`model_list:`. Add:

```yaml
litellm_settings:
  extra_spend_tag_headers:
    - "x-claude-code-session-id"
```

**Deploy:** the chezmoi source `private_projects/private_gamuda/litellm-tracker/`
maps to `~/projects/gamuda/litellm-tracker/` (the `private_` attribute is stripped
from each name), which is the path `cv` uses and the compose file mounts. So on
onyx: `chezmoi apply`, then `cd ~/projects/gamuda/litellm-tracker && docker compose up -d`
to reload (config is mounted read-only, so the container must restart).

## Component 2 — statusline gating

Replace the current `show_cost` gate (true when `CLAUDE_CODE_USE_VERTEX` **or**
`ANTHROPIC_BASE_URL`) with a three-way decision:

| Condition | Cost segment source |
|---|---|
| `ANTHROPIC_BASE_URL` set (the `cv`/LiteLLM path) | **ledger per-session** (new) |
| else `CLAUDE_CODE_USE_VERTEX` set | Claude Code's `.cost.total_cost_usd` (unchanged) |
| else | no cost segment (unchanged) |

`session_id` is already parsed from the input JSON; `base` comes from
`ANTHROPIC_BASE_URL`, bearer from `ANTHROPIC_AUTH_TOKEN`.

## Component 3 — read path (cache + throttled background refresh)

The statusline repaints many times per second and must never curl inline.

- **Cache file:** `${TMPDIR:-/tmp}/claude-cc-cost.<session_id>` — contents are a
  single USD number (e.g. `0.42`).
- **On each render:** read the cached number for display. If the file is missing
  or its mtime is older than `TTL` (~30s), launch a **detached** background
  refresh: `( refresh >/dev/null 2>&1 & )` so no fd to Claude Code's captured
  stdout is held and the script returns immediately.
- **Stampede guard:** the refresh takes an `mkdir "${cache}.lock"` (atomic) before
  running and `rmdir`s it after; a lock dir older than ~60s is treated as stale
  and removed (covers a crashed refresh). Rapid repaints and same-session panes
  thus collapse to one in-flight refresh.
- **Refresh body:**
  `GET $ANTHROPIC_BASE_URL/spend/logs?start_date=<today-1>&end_date=<today+1>&summarize=false`
  with `curl -fsS -m 5 -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN"`. The
  ±1-day window dodges UTC/local-TZ edges and comfortably contains a session's
  lifetime. Sum `spend` over entries whose `request_tags` contain this
  `session_id`; write the total atomically (`> tmp && mv`). Curl/jq failure →
  leave the existing cache untouched (show last known; no error text on the
  statusline).

## Component 4 — display

- Format unchanged: `$X.XX` via `awk`.
- `color_for_cost` thresholds recalibrated for per-session magnitude (the current
  $20/$50/$75/$100 ramp is for account-wide totals): gray `<$3`, green `<$9`,
  yellow `<$18`, orange `<$30`, red `≥$30`. Tunable; lives in one `awk` block.
- Blank until the first successful fetch; `$0.00` once the proxy confirms zero
  spend for the session.

## Component 5 — pure function + tests

Extract the ledger-summing logic into a pure, network-free function:

```
session_spend <logs_json> <session_id>   # → USD total (e.g. "0.42"), "0" on no match
```

It filters `request_tags` defensively, because the exact stored shape (raw value
vs `"x-claude-code-session-id: <value>"`) is confirmed once against a real log
entry during implementation:

```
jq -r --arg s "$sid" '[.[] | select(
    (.request_tags // []) as $t
    | ($t | index($s)) or any($t[]; . | contains($s))
  ) | .spend] | add // 0'
```

Unit tests mirror `dot_tmux/scripts/tests/test-claude-cost.sh` (a sibling test
script for the statusline), with fixtures for: tag present (single + multiple
entries summed), tag absent, malformed/empty JSON, and the `header: value` tag
shape. No network.

**Manual verification:** run a `cv` session, issue a request, wait for the spend
log to land, and confirm the statusline figure tracks the per-model totals shown
by `prefix + u`.

## Files touched

- `private_projects/private_gamuda/litellm-tracker/config.yaml` — add
  `litellm_settings.extra_spend_tag_headers`.
- `dot_claude/executable_statusline.sh` — three-way gating, per-session cache
  read, detached throttled background refresh, `session_spend` pure function,
  recalibrated `color_for_cost`.
- New `session_spend` test script (statusline sibling of the popup's
  `test-claude-cost.sh`).
- This spec; reference the superseded non-goal in
  `2026-06-24-litellm-cost-popup-design.md`.

## Edge cases

- **Proxy unreachable** → curl fails, cache untouched, show last known or blank.
- **`session_id` missing from input** → no cache key; show no cost segment.
- **Brand-new session, no spend yet** → blank until first fetch returns; then
  `$0.00`.
- **Stale lock dir** (crashed refresh) → broken after ~60s by mtime.
- **Session spans midnight** → the ±1-day window still covers it; a multi-day
  session beyond the window under-counts the oldest tail (rare; acceptable).
- **`set -u` / `set -e`** → match the existing script's options; guard all env and
  cache reads.

## Related

- `2026-06-24-litellm-cost-popup-design.md` — the `prefix + u` ledger popup
  (same data source; supersedes its statusline non-goal).
- `2026-06-24-route-cv-through-litellm-design.md` — why `cv` uses the proxy.
- Memory: `tmux-popup-env-propagation`, `cv-routes-through-litellm`.
