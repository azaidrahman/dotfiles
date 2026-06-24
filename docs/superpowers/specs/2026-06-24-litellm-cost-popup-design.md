# Per-session LiteLLM detection + ledger cost for `prefix + u`

**Date:** 2026-06-24
**Status:** Implemented (`main` @ `2acec06`)
**Supersedes:** `2026-06-24-vertex-cost-breakdown-popup-design.md` — the
Vertex/local-transcript approach below replaced it once `cv` moved off native
Vertex onto the LiteLLM proxy (see
`2026-06-24-route-cv-through-litellm-design.md`).

## Problem

After `cv` switched from native Vertex to the LiteLLM proxy, the `prefix + u`
popup (`dot_tmux/scripts/executable_claude-usage.sh`) was wrong in two ways:

1. **Wrong view.** It chose between the usage-bar view and the cost view by
   curling the proxy's `/health/liveliness`. The onyx proxy is *always* up and
   reachable over Tailscale, so the check passed even in a plain subscription
   `claude` session — which then saw the cost view instead of `/usage`.
2. **Wrong number.** The cost view summed **all** local
   `~/.claude/projects/**/*.jsonl` transcripts and re-priced them at Vertex
   list rates — i.e. every session's spend, estimated, not what LiteLLM
   actually logged.

Root cause of (1): **proxy liveness answers "is the proxy up?", not "is *this*
session routing through it?"** The popup is a fresh shell that can't see the
`ANTHROPIC_BASE_URL` `cv` sets as a per-process prefix env var.

## Goal

`prefix + u` shows the cost view **iff the session in the triggering pane is
routed through LiteLLM**, and the cost number is the **proxy's own ledger**, not
a local estimate. Subscription sessions keep the unchanged `/usage` bar view.

## Non-goals

- Cache-token split in the cost view (LiteLLM's free OSS endpoints don't expose
  it per model; only spend per model).
- Claude-only filtering of the ledger — the proxy is the unified AI-cost tracker
  (it also serves Gemini via `piv`), so all models with spend are shown.
- Touching the statusline `$` segment — `statusline.sh` runs as a child of the
  `claude` process, sees `ANTHROPIC_BASE_URL` directly, and already uses Claude
  Code's own reported `cost.total_cost_usd`. Correct as-is.

## Detection: per-pane marker

The reliable "does this session use LiteLLM" signal is published by `cv` as a
**pane-scoped tmux option**, not session-environment (which leaks across panes):

- `cv` runs `tmux set -p @claude_provider litellm` on launch and
  `tmux set -pu @claude_provider` on exit (guarded by `[[ -n "$TMUX" ]]`).
- The popup reads `tmux show-options -pqv -t <pane> @claude_provider`.

Pane-scoped means a subscription pane and a `cv` pane side-by-side each report
correctly. `provider_tag()` and the view-gating in `main()` both read it.

### Resolving the triggering pane (the subtle bit)

`tmux display-popup -E "<cmd> #{pane_id}"` does **NOT** expand formats in its
command string — `#{pane_id}` reaches the script as the literal text
`#{pane_id}`. (`run-shell` *does* expand it; `display-popup` does not.) So the
pane id cannot be passed as a command argument.

Fix: the script **self-resolves** via `tmux display-message -p '#{pane_id}'`
from inside the popup, which returns the session's **active pane** — exactly the
pane that opened the popup (a popup overlay does not steal active-pane status).
`main()` keeps a real `%N` arg if one is ever supplied, else self-resolves.

## Cost source: LiteLLM ledger

The proxy's own spend, via OSS-free endpoints (the richer
`/global/spend/report` is Enterprise-gated):

| Endpoint | Used for |
|---|---|
| `/global/spend/models` | per-model bars (`total_spend`, `model`) — all-time |
| `/global/spend` | all-time grand total |
| `/global/spend/logs` | daily `[{date, spend}]`, summed for the last-7-day total |

The popup is `bash` and never sources `~/.zshenv`, so it gets the master key
from `~/.config/zsh/secrets.zsh` (`litellm_key()` greps the
`export LITELLM_MASTER_KEY=` line) — env var first if present. `litellm_curl()`
is a thin authenticated GET. `cost_blob()` folds the three JSON responses into a
cacheable, render-ready text blob (pure, no network — unit-tested). Zero-spend
models are dropped and the `vertex_ai/` provider prefix stripped for width.

## Output layout

```
  Cost · LiteLLM ledger
  provider: LiteLLM (http://localhost:4000)

  gemini-3.1-pro-preview   ████████████████████████████████ $1.40
  claude-opus-4-8          ████████████████████░░░░░░░░░░░░ $0.89
  claude-sonnet-4-6        ████████░░░░░░░░░░░░░░░░░░░░░░░░ $0.36
  gemini-3.5-flash         █████░░░░░░░░░░░░░░░░░░░░░░░░░░░ $0.23
  ──────────────────────────────────────────────────────────
  Total · last 7 days                                     $0.78
  all-time                                                 $2.88
```

## Files touched

- `dot_tmux/scripts/executable_claude-usage.sh` — marker detection +
  self-resolution, ledger fetch/parse/render, key sourcing. Removed the Vertex
  pricing table and the local-transcript `cost_compute`.
- `dot_tmux/conf.d/keys.conf` — binding comment (no `#{pane_id}` arg).
- `dot_config/zsh/functions/cv` — set/unset the `@claude_provider` marker.
- `dot_tmux/scripts/tests/test-claude-cost.sh` — rewritten for `cost_blob` +
  `render_cost` (no network).

## Edge cases

- **Proxy unreachable** → render header + dim "proxy unreachable — could not
  fetch spend" (the marker says LiteLLM but the ledger is unavailable).
- **No spend logged** → dim "no spend recorded by the proxy".
- **Marker absent / unknown pane** → falls through to the unchanged `/usage`
  view (the safe default).
- **`set -u`** → script runs under `set -u`; all marker/env reads are guarded.

## Related

- `2026-06-24-route-cv-through-litellm-design.md` — why `cv` uses the proxy.
- Memory: `tmux-popup-env-propagation` records both tmux gotchas above.
