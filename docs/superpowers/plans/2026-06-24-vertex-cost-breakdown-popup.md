# Vertex cost-breakdown popup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `CLAUDE_CODE_USE_VERTEX` is set, make `prefix + u` render a 7-day Claude spend breakdown by token type instead of the (empty-on-Vertex) subscription rate-limit bars.

**Architecture:** A single Vertex branch inside the existing tmux popup script `dot_tmux/scripts/executable_claude-usage.sh`. The existing rate-limit flow is wrapped in a `usage_main` function (unchanged behavior); a new `cost_main` flow computes spend from local transcript JSONL via one `jq` pass against a hardcoded Vertex pricing table, then renders bars with the script's existing helpers. The script is made source-safe so the pure-computation function (`cost_compute`) can be unit-tested with fixture transcripts.

**Tech Stack:** bash, jq, tmux `display-popup`, chezmoi.

## Global Constraints

- Only one file ships behavior: `dot_tmux/scripts/executable_claude-usage.sh` (chezmoi source; deploys to `~/.tmux/scripts/claude-usage.sh`).
- Reuse existing helpers (`bar`, `repeat`, `color_for`, `render`, color vars) — do not duplicate them.
- Subscription (non-Vertex) path must behave exactly as today.
- Pricing table (USD per 1M tokens), family-substring matched, flat (no long-context tier):
  - `opus`:   in 5,  out 25, cache-write 6.25, cache-read 0.50
  - `sonnet`: in 3,  out 15, cache-write 3.75, cache-read 0.30
  - `haiku`:  in 1,  out 5,  cache-write 1.25, cache-read 0.10
  - `fable`:  in 10, out 50, cache-write 12.5, cache-read 1.00
- Cache-write priced at flat 1.25× (5-minute rate) — accepted approximation.
- Unrecognized models → summed into an `other` token count (priced $0), surfaced as a flag line; never silently dropped.
- Window: last 7 days, cutoff applied per-line by `.timestamp` (epoch compare).
- Tests live at `dot_tmux/scripts/tests/test-claude-cost.sh` and must NOT be deployed by chezmoi (add target path to `.chezmoiignore`).

---

### Task 1: Make the script source-safe (no behavior change)

Wrap the existing top-level execution so the file can be `source`d by tests without launching the popup, and add the Vertex/subscription branch point.

**Files:**
- Modify: `dot_tmux/scripts/executable_claude-usage.sh` (top-level flow at lines ~87-106)
- Test: `dot_tmux/scripts/tests/test-claude-cost.sh` (create)
- Modify: `.chezmoiignore` (create if missing)

**Interfaces:**
- Produces: `usage_main()` (wraps the existing cache-draw → fetch → render → keypress flow, verbatim), and a bottom-of-file guard `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"` where `main` dispatches on `$CLAUDE_CODE_USE_VERTEX`.

- [ ] **Step 1: Write the failing test**

Create `dot_tmux/scripts/tests/test-claude-cost.sh`:

```bash
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

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash dot_tmux/scripts/tests/test-claude-cost.sh`
Expected: FAIL — sourcing the current script runs the popup flow (clears screen / blocks on keypress / extra output), so the last line is not `SOURCED_OK`.

- [ ] **Step 3: Wrap the existing flow and add the guard**

In `executable_claude-usage.sh`, take the existing top-level block (the comment `# 1. instant draw from cache...` through the keypress handling at the end) and wrap it verbatim in a function:

```bash
usage_main() {
  # 1. instant draw from cache (or a loading placeholder)
  if [[ -s $CACHE ]]; then
    render "$(cat "$CACHE")" "(cached — refreshing…)"
  else
    clear 2>/dev/null
    echo
    printf '  %sClaude Code usage%s\n\n  %sLoading…%s\n' "$c_bold" "$c_reset" "$c_dim" "$c_reset"
  fi

  # 2. fetch fresh, cache, redraw
  FRESH=$(claude -p /usage 2>&1)
  printf '%s\n' "$FRESH" > "$CACHE"
  render "$FRESH" ""

  echo
  printf '  %s[any key to close]%s' "$c_dim" "$c_reset"
  old_stty=$(stty -g 2>/dev/null)
  stty -echo -icanon min 1 time 0 2>/dev/null
  dd bs=1 count=1 >/dev/null 2>&1
  [ -n "$old_stty" ] && stty "$old_stty" 2>/dev/null
}

main() {
  if [ -n "${CLAUDE_CODE_USE_VERTEX:-}" ]; then
    cost_main
  else
    usage_main
  fi
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
```

Leave `cost_main` undefined for now (Task 4 adds it); the guard means it is never reached when sourced. Keep `CACHE`, the color vars, and all helper functions (`color_for`, `to_countdown`, `repeat`, `bar`, `render`) defined at top level above `usage_main` so both flows and tests can use them.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash dot_tmux/scripts/tests/test-claude-cost.sh`
Expected: `ok   - source is side-effect free`, exit 0.

- [ ] **Step 5: Stop chezmoi from deploying the tests**

Add the deploy-target path to `.chezmoiignore` (create the file if it does not exist):

```
.tmux/scripts/tests
```

- [ ] **Step 6: Commit**

```bash
git add dot_tmux/scripts/executable_claude-usage.sh dot_tmux/scripts/tests/test-claude-cost.sh .chezmoiignore
git -c commit.gpgsign=false commit -m "refactor(tmux): make claude-usage.sh source-safe, add vertex branch point"
```

---

### Task 2: `cost_compute` — pricing math over transcripts

A pure function: given a cutoff epoch and a list of JSONL files, emit per-token-type dollar totals.

**Files:**
- Modify: `dot_tmux/scripts/executable_claude-usage.sh` (add function + pricing constant)
- Test: `dot_tmux/scripts/tests/test-claude-cost.sh` (extend)

**Interfaces:**
- Produces: `cost_compute <cutoff_epoch> <file>...` → writes to stdout, one `key value` per line:
  `input <usd>`, `output <usd>`, `cache_write <usd>`, `cache_read <usd>`, `total <usd>`, `other_tokens <int>`, `other_models <csv>`. Dollar values are raw jq numbers (not yet formatted). A cutoff of `0` disables time filtering (used by tests).
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the failing tests**

Append to `dot_tmux/scripts/tests/test-claude-cost.sh` (before `exit $fail`). Create fixtures with clean round numbers so costs are exact:

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash dot_tmux/scripts/tests/test-claude-cost.sh`
Expected: FAIL — `cost_compute: command not found` / empty values.

- [ ] **Step 3: Implement `cost_compute` and the pricing constant**

Add near the top of the script (after the color vars, before `usage_main`):

```bash
# Vertex per-1M-token pricing (USD). Family-substring matched; flat (no long-context tier).
# cache-write = 5-minute rate (1.25x input); accepted approximation.
COST_PRICE_JSON='{
  "opus":  {"in":5, "out":25,"cw":6.25,"cr":0.5},
  "sonnet":{"in":3, "out":15,"cw":3.75,"cr":0.3},
  "haiku": {"in":1, "out":5, "cw":1.25,"cr":0.1},
  "fable": {"in":10,"out":50,"cw":12.5,"cr":1.0}
}'

# cost_compute <cutoff_epoch> <file>... : sum spend by token type. cutoff 0 = no time filter.
cost_compute() {
  local cutoff=$1; shift
  [ "$#" -eq 0 ] && { printf 'input 0\noutput 0\ncache_write 0\ncache_read 0\ntotal 0\nother_tokens 0\nother_models \n'; return; }
  cat "$@" 2>/dev/null | jq -nrR --argjson cutoff "$cutoff" --argjson price "$COST_PRICE_JSON" '
    def family($m): ($m // "") | ascii_downcase as $l
      | if   ($l|test("opus"))   then "opus"
        elif ($l|test("sonnet")) then "sonnet"
        elif ($l|test("haiku"))  then "haiku"
        elif ($l|test("fable"))  then "fable"
        else "other" end;
    def epoch($t): ($t // "") | sub("\\.[0-9]+Z$";"Z") | (try fromdateiso8601 catch 0);
    reduce (inputs | (fromjson? // empty)) as $e
      ({input:0,output:0,cw:0,cr:0,other_tok:0,others:{}};
        if ($e.type=="assistant") and ($e.message.usage != null)
           and (epoch($e.timestamp) >= $cutoff)
        then
          family($e.message.model) as $f
          | $e.message.usage as $u
          | (($u.input_tokens // 0)) as $it
          | (($u.output_tokens // 0)) as $ot
          | (($u.cache_creation_input_tokens // 0)) as $ct
          | (($u.cache_read_input_tokens // 0)) as $rt
          | if $f=="other"
            then .other_tok += ($it+$ot+$ct+$rt) | .others[($e.message.model // "unknown")] = true
            else $price[$f] as $p
              | .input  += $it*$p.in/1000000
              | .output += $ot*$p.out/1000000
              | .cw     += $ct*$p.cw/1000000
              | .cr     += $rt*$p.cr/1000000
            end
        else . end)
    | .total = (.input + .output + .cw + .cr)
    | "input \(.input)\noutput \(.output)\ncache_write \(.cw)\ncache_read \(.cr)\ntotal \(.total)\nother_tokens \(.other_tok)\nother_models \((.others|keys|join(",")))"
  '
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash dot_tmux/scripts/tests/test-claude-cost.sh`
Expected: all `ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add dot_tmux/scripts/executable_claude-usage.sh dot_tmux/scripts/tests/test-claude-cost.sh
git -c commit.gpgsign=false commit -m "feat(tmux): add cost_compute pricing pass for vertex spend"
```

---

### Task 3: `render_cost` — draw the breakdown

Turn `cost_compute` output into the bar layout, reusing existing helpers.

**Files:**
- Modify: `dot_tmux/scripts/executable_claude-usage.sh` (add function)
- Test: `dot_tmux/scripts/tests/test-claude-cost.sh` (extend)

**Interfaces:**
- Consumes: `cost_compute` stdout (Task 2).
- Produces: `render_cost <compute_output>` → prints header, four labeled bars (Input / Output / Cache write / Cache read) with `$X.XX` amounts, a rule, a `Total` line, and (only if `other_tokens > 0`) a dim flag line naming the unpriced models. Bars scale to the largest of the four values. Empty/zero spend → header + a dim "no spend in the last 7 days" line.

- [ ] **Step 1: Write the failing tests**

Append before `exit $fail`. Strip ANSI so assertions are stable:

```bash
strip() { sed $'s/\033\\[[0-9;]*m//g'; }
res=$(cost_compute 0 "$TMP/opus.jsonl")
out=$(render_cost "$res" | strip)
check "render shows input dollars"  "1" "$(printf '%s\n' "$out" | grep -c 'Input .* \$5\.00')"
check "render shows total dollars"  "1" "$(printf '%s\n' "$out" | grep -c 'Total .* \$36\.75')"
check "render has no other line"    "0" "$(printf '%s\n' "$out" | grep -c 'untracked')"

res=$(cost_compute 0 "$TMP/other.jsonl")
out=$(render_cost "$res" | strip)
check "render flags unpriced model" "1" "$(printf '%s\n' "$out" | grep -c 'claude-zzz-9')"

out=$(render_cost "$(cost_compute 1700000000 "$TMP/old.jsonl")" | strip)
check "render empty-spend fallback" "1" "$(printf '%s\n' "$out" | grep -c 'no spend in the last 7 days')"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash dot_tmux/scripts/tests/test-claude-cost.sh`
Expected: FAIL — `render_cost: command not found`.

- [ ] **Step 3: Implement `render_cost`**

Add after `cost_compute`. Reuse `repeat`, `color_for`, and the color vars; mirror the `bar()` label/width feel but with dollar amounts:

```bash
# render_cost <compute_output> : draw the 7-day cost breakdown.
render_cost() {
  local data=$1 v
  v() { printf '%s\n' "$data" | grep "^$1 " | cut -d' ' -f2-; }
  local in=$(v input) out=$(v output) cw=$(v cache_write) cr=$(v cache_read)
  local total=$(v total) other=$(v other_tokens) models=$(v other_models)

  clear 2>/dev/null
  echo
  printf '  %sCost · last 7 days%s\n\n' "$c_bold" "$c_reset"

  # zero spend → fallback
  if awk -v t="${total:-0}" 'BEGIN{exit !(t+0==0)}'; then
    printf '  %sno spend in the last 7 days%s\n' "$c_dim" "$c_reset"
    return
  fi

  local max; max=$(awk -v a="$in" -v b="$out" -v c="$cw" -v d="$cr" \
    'BEGIN{m=a;if(b>m)m=b;if(c>m)m=c;if(d>m)m=d; if(m<=0)m=1; print m}')
  local width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
  local bar_w=$(( width - 34 )); (( bar_w < 8 )) && bar_w=8; (( bar_w > 32 )) && bar_w=32

  costbar() { # label value
    local label=$1 val=$2 fill empty pct
    pct=$(awk -v v="$val" -v m="$max" 'BEGIN{printf "%d", (v/m)*100}')
    fill=$(( pct * bar_w / 100 )); (( fill < 0 )) && fill=0; (( fill > bar_w )) && fill=bar_w
    empty=$(( bar_w - fill ))
    printf '  %-12s %s%s%s%s%s %s$%0.2f%s\n' \
      "$label" "$(color_for "$pct")" "$(repeat █ "$fill")" "$c_dim" "$(repeat ░ "$empty")" \
      "$c_reset" "$c_bold" "$val" "$c_reset"
  }
  costbar "Input"       "$in"
  costbar "Output"      "$out"
  costbar "Cache write" "$cw"
  costbar "Cache read"  "$cr"
  printf '  %s%s%s\n' "$c_dim" "$(repeat ─ $(( bar_w + 12 )))" "$c_reset"
  printf '  %-12s %*s%s$%0.2f%s\n' "Total" "$bar_w" "" "$c_bold" "$total" "$c_reset"

  if [ "${other:-0}" -gt 0 ] 2>/dev/null && [ "$other" != "0" ]; then
    printf '\n  %s+ untracked model(s): %s — add to pricing table%s\n' "$c_dim" "$models" "$c_reset"
  fi
}
```

Note: `printf '%0.2f'` requires the value be a number; jq emits bare numbers (e.g. `5`, `36.75`), which `printf` accepts.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash dot_tmux/scripts/tests/test-claude-cost.sh`
Expected: all `ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add dot_tmux/scripts/executable_claude-usage.sh dot_tmux/scripts/tests/test-claude-cost.sh
git -c commit.gpgsign=false commit -m "feat(tmux): render vertex cost breakdown bars"
```

---

### Task 4: `cost_main` — wire the flow with cache + redraw

Glue: collect transcripts, compute, render, cache, and the instant-draw-then-refresh pattern.

**Files:**
- Modify: `dot_tmux/scripts/executable_claude-usage.sh` (add function)
- Test: manual (popup behavior can't be unit-tested)

**Interfaces:**
- Consumes: `cost_compute` (Task 2), `render_cost` (Task 3); `main` dispatch (Task 1).
- Produces: `cost_main()` — used by `main` when `$CLAUDE_CODE_USE_VERTEX` is set.

- [ ] **Step 1: Implement `cost_main`**

Add after `render_cost`. Use a separate cache file from the usage path:

```bash
COST_CACHE="${TMPDIR:-/tmp}/claude-cost.cache"

cost_main() {
  # instant draw from cache (computed compute-output is what we cache)
  if [[ -s $COST_CACHE ]]; then
    render_cost "$(cat "$COST_CACHE")"
    printf '\n  %s(cached — refreshing…)%s\n' "$c_dim" "$c_reset"
  else
    clear 2>/dev/null
    echo
    printf '  %sCost · last 7 days%s\n\n  %sLoading…%s\n' "$c_bold" "$c_reset" "$c_dim" "$c_reset"
  fi

  # fresh compute over last-7-day transcripts
  local cutoff; cutoff=$(( $(date +%s) - 7*86400 ))
  local files=()
  while IFS= read -r f; do files+=("$f"); done < <(find "$HOME/.claude/projects" -name '*.jsonl' -mtime -7 2>/dev/null)
  local fresh; fresh=$(cost_compute "$cutoff" "${files[@]}")
  printf '%s\n' "$fresh" > "$COST_CACHE"
  render_cost "$fresh"

  echo
  printf '  %s[any key to close]%s' "$c_dim" "$c_reset"
  local old_stty; old_stty=$(stty -g 2>/dev/null)
  stty -echo -icanon min 1 time 0 2>/dev/null
  dd bs=1 count=1 >/dev/null 2>&1
  [ -n "$old_stty" ] && stty "$old_stty" 2>/dev/null
}
```

- [ ] **Step 2: Re-run the unit tests (no regressions)**

Run: `bash dot_tmux/scripts/tests/test-claude-cost.sh`
Expected: all `ok`, exit 0 (sourcing still side-effect free; `cost_main` defined but unreached when sourced).

- [ ] **Step 3: Manual smoke test — subscription path unchanged**

Run: `bash dot_tmux/scripts/executable_claude-usage.sh`
Expected: the existing `/usage` rate-limit bars render exactly as before; any key closes.

- [ ] **Step 4: Manual smoke test — Vertex path**

Run: `CLAUDE_CODE_USE_VERTEX=1 bash dot_tmux/scripts/executable_claude-usage.sh`
Expected: the `Cost · last 7 days` breakdown renders with four bars + total over your real transcripts; any key closes. (If you have no Vertex/recent usage it still totals all recent local transcripts — that's expected; the math is provider-agnostic, only the trigger is Vertex.)

- [ ] **Step 5: Deploy via chezmoi and verify the live popup**

Run: `chezmoi apply --include=scripts ~/.tmux/scripts/claude-usage.sh` (or `chezmoi apply`)
Then in tmux: `prefix + u` under a normal session (rate-limit bars) and under a `cv`/Vertex session (cost breakdown).
Expected: both render correctly in the real popup.

- [ ] **Step 6: Commit**

```bash
git add dot_tmux/scripts/executable_claude-usage.sh
git -c commit.gpgsign=false commit -m "feat(tmux): vertex cost breakdown on prefix+u popup"
```

---

## Notes for the implementer

- Commit signing is failing in this environment ("Couldn't find key in agent"); every commit uses `-c commit.gpgsign=false`. If your agent has the signing key loaded, drop that flag.
- The chezmoi source file name (`executable_claude-usage.sh`) encodes the executable bit; edit it in place under `~/.local/share/chezmoi/`, never the deployed `~/.tmux/scripts/claude-usage.sh`.
- After all tasks, consider running the repo's `chezmoi-sync` skill to push.
