# Vertex cost-breakdown mode for `prefix + u`

**Date:** 2026-06-24
**Status:** Approved design, pending implementation

## Problem

The `prefix + u` tmux popup (`dot_tmux/scripts/executable_claude-usage.sh`)
renders `claude -p /usage` as colored percentage bars — 5h / 7d subscription
rate-limit usage. When Claude runs against Vertex (`cv`, i.e.
`CLAUDE_CODE_USE_VERTEX` set), there are no subscription rate limits, so `/usage`
returns nothing useful. On Vertex the meaningful signal is **spend**, not usage
percentage.

## Goal

When `CLAUDE_CODE_USE_VERTEX` is set, `prefix + u` shows a **7-day cost
breakdown by token type** (input / output / cache-write / cache-read) computed
from the local transcript JSONL files. When it is not set, the popup behaves
exactly as today.

## Non-goals

- Per-day spend bars (decided against — aggregate only).
- Per-model breakdown (decided against — token-type breakdown only).
- Exact 1h-vs-5m cache-write pricing (accepted approximation — see below).
- Changing the statusline cost segment (already exists and is Vertex-gated).

## Data source

Claude Code transcripts live at
`~/.claude/projects/<slug>/<session-id>.jsonl`. Each assistant message carries
`.message.usage` with the four token counters needed:

```json
"usage": {
  "input_tokens": 2,
  "cache_creation_input_tokens": 940,
  "cache_read_input_tokens": 55615,
  "output_tokens": 428
}
```

and `.message.model` (e.g. `claude-opus-4-8`) plus a top-level `.timestamp`
(ISO-8601) on each line.

## Pricing table

Vertex bills Claude at Anthropic's published per-MTok list rates. Opus 4.8's 1M
context has **no long-context premium**, so pricing is flat across the whole
window — no 200K-token tier split.

| Model | input | output | cache-write (5m, 1.25×) | cache-read (0.1×) |
|---|---|---|---|---|
| `claude-opus-4-8` | $5 | $25 | $6.25 | $0.50 |
| `claude-sonnet-4-6` | $3 | $15 | $3.75 | $0.30 |
| `claude-haiku-4-5` | $1 | $5 | $1.25 | $0.10 |
| `claude-fable-5` | $10 | $50 | $12.50 | $1.00 |

Matching is by family substring (so future point versions of a family still
slot in): `*opus*`, `*sonnet*`, `*haiku*`, `*fable*`. Token counts for an
unrecognized model are summed into a flagged **"other"** line (priced at $0) so
the rendered total is never silently understated — the line's presence signals
"add this model to the table."

### Accepted approximation

`cache_creation_input_tokens` is priced at the 5-minute cache-write rate
(1.25× input). Claude Code also uses 1h-TTL cache (2×) for some blocks; the
transcript carries a finer breakdown under
`.message.usage.cache_creation.{ephemeral_5m_input_tokens,ephemeral_1h_input_tokens}`
that could be used for exactness. We deliberately use flat 1.25×. Documented as
a future refinement, not built.

## Architecture

A single branch inside the existing `claude-usage.sh` — no new file, no new
keybinding.

1. **Branch at the top** on `$CLAUDE_CODE_USE_VERTEX`:
   - unset → existing `/usage` rate-limit-bar path, unchanged.
   - set → new cost path (below).
2. **Collect** candidate transcripts:
   `find ~/.claude/projects -name '*.jsonl' -mtime -7` (mtime is a coarse
   pre-filter; the precise 7-day cutoff is applied per-line in step 3).
3. **Compute** with one `jq` pass over the collected files:
   - keep only lines that are assistant messages with `.message.usage`;
   - keep only lines whose `.timestamp` is within the true 7-day window (cutoff
     epoch passed in via `--argjson`);
   - bucket each line's model name to a family key (or `other`);
   - multiply each token counter by the per-MTok rate from a pricing table
     passed in via `--argjson` and accumulate per token type;
   - emit four totals (input / output / cache-write / cache-read) plus grand
     total and an `other` token count.
4. **Render** the four token-type bars + a total line, reusing the existing
   `bar()` / `repeat()` / `color_for()` helpers. Bars scale to the largest of
   the four line values. If `other` token count > 0, append a dim flag line
   naming the unpriced models.
5. **Cache** to a separate `${TMPDIR}/claude-cost.cache`, using the same
   instant-draw-from-cache → refresh → redraw pattern the script already uses
   for the usage path.

## Output layout

```
  Cost · last 7 days

  Input        ▓▓░░░░░░  $0.90
  Output       ▓▓▓▓▓▓░░  $4.20
  Cache write  ▓▓▓░░░░░  $2.10
  Cache read   ▓░░░░░░░  $0.55
  ───────────────────
  Total                $7.75
```

(With an unpriced model present, a trailing dim line such as
`  + untracked model(s): claude-foo-9 — add to pricing table`.)

## Files touched

- `dot_tmux/scripts/executable_claude-usage.sh` — the branch, the jq computation,
  the cost renderer, the cost cache. Everything else (keybinding, usage path,
  helper functions) is reused unchanged.

## Edge cases

- **No Vertex transcripts in 7 days** → render the header + a dim "no spend in
  the last 7 days" line (mirrors the usage path's empty fallback).
- **No `jq`** → already a dependency of the repo's statusline; assume present.
  If absent, fall through to printing the raw computation error rather than a
  blank popup.
- **Malformed / partial JSONL lines** → `jq` per-line filtering with `?` /
  `fromjson?`-style guards so one bad line doesn't abort the pass.
- **Clock/timezone** → the 7-day cutoff is computed in epoch seconds; `.timestamp`
  is ISO-8601 UTC, compared as epoch. No local-tz math.
