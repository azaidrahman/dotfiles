# Project A: Route `cv` (Claude Code on Vertex) through LiteLLM

**Date:** 2026-06-24
**Status:** Approved design, pending implementation
**Relation:** Foundation for Project B (cost popup reads LiteLLM `/spend`). B is blocked on this.

## Problem

`cv` runs Claude Code against Vertex natively (`CLAUDE_CODE_USE_VERTEX=1`, `ANTHROPIC_VERTEX_PROJECT_ID`, direct to Vertex). The local LiteLLM proxy (`litellm-tracker`, `localhost:4000`, OrbStack docker-compose + Postgres) therefore never sees Claude Code traffic and has no cost data for it. The goal is unified, real-time spend tracking across all LLM tools by making LiteLLM the single gateway — starting with routing Claude Code through it.

## Goal

`cv` launches Claude Code routed through the LiteLLM proxy, with full feature fidelity (prompt caching, 1M context, extended thinking, tool use, streaming) and Haiku available for background calls, so every Claude Code request is logged by LiteLLM's spend DB.

## Non-goals

- The cost popup / statusline cost display — that's **Project B** (reads `/spend`).
- Routing other tools (`ov`/opencode already uses LiteLLM for Gemini).
- A native-Vertex fallback — the native path is **replaced** (user decision).

## Feasibility (verified via spike, 2026-06-24)

Against `localhost:4000` `/v1/messages` on `claude-opus-4-8`:
- **Prompt caching** forwarded faithfully: write → `cache_creation_input_tokens=16204`; repeat → `cache_read_input_tokens=16204` (incl. 5m/1h split).
- **Extended thinking** (`adaptive`) → `["thinking","text"]`, no error.
- **Tool use** → `stop_reason=tool_use`, `tool_use` block present.
- **Streaming** → SSE events delivered.
- **Spend logging** → `/spend/logs` records per-request `spend`, `model`, `total_tokens` (cache-token split is `null` in the log — relevant to Project B, not A).
- **1M context:** model name `claude-opus-4-8[1m]` → **400** (no such model registered); plain `claude-opus-4-8` + header `anthropic-beta: context-1m-2025-08-07` → **200** (LiteLLM forwards the 1M beta). ⇒ register aliases for the exact model strings `cv` sends.

## Design

### 1. LiteLLM config — register `cv`'s model strings

File: `private_projects/private_gamuda/litellm-tracker/config.yaml`. Add `model_list` entries whose `model_name` matches exactly what Claude Code puts on the wire, mapped to the Vertex target, with the 1M beta forced on the `[1m]` variants:

```yaml
  - model_name: "claude-opus-4-8[1m]"
    litellm_params:
      model: vertex_ai/claude-opus-4-8
      vertex_project: "os.environ/GCP_PROJECT_ID"
      vertex_location: "global"
      extra_headers: {"anthropic-beta": "context-1m-2025-08-07"}
  - model_name: "claude-sonnet-4-6[1m]"
    litellm_params:
      model: vertex_ai/claude-sonnet-4-6
      vertex_project: "os.environ/GCP_PROJECT_ID"
      vertex_location: "global"
      extra_headers: {"anthropic-beta": "context-1m-2025-08-07"}
  - model_name: "claude-haiku-4-5@20251001"
    litellm_params:
      model: vertex_ai/claude-haiku-4-5
      vertex_project: "os.environ/GCP_PROJECT_ID"
      vertex_location: "global"
```

Keep the existing plain `claude-opus-4-8` / `claude-sonnet-4-6` / gemini entries (used by `ov` and as fallbacks). Haiku is **required** — Claude Code uses it for background tasks; without it those calls 404.

**Verification gate during implementation:** confirm the on-wire model string Claude Code actually sends (via the proxy's `--detailed_debug` log) and ensure a matching `model_name` exists. If Claude Code strips `[1m]` and instead sends plain name + the 1M beta header, the plain entries already cover it; the `[1m]` aliases are harmless belt-and-suspenders. Add whichever the log shows is needed.

### 2. Rewrite `cv`

File: `dot_config/zsh/functions/cv`. New behavior:

1. **Proxy guard (auto-start, else abort)** before launching:
   - `GET http://localhost:4000/health/liveliness` (short timeout).
   - If not healthy: `docker compose -f <litellm-tracker dir> up -d`, then poll health for ~20s.
   - If still unhealthy, or `docker`/OrbStack unavailable: print the exact start command and **return non-zero without launching claude**.
2. **Route through LiteLLM:**
   - `export ANTHROPIC_BASE_URL=http://localhost:4000`
   - `ANTHROPIC_AUTH_TOKEN=$LITELLM_MASTER_KEY` (Claude Code auth to the proxy)
   - **Unset / do not set** `CLAUDE_CODE_USE_VERTEX`, `ANTHROPIC_VERTEX_PROJECT_ID`, `CLOUD_ML_REGION` — LiteLLM owns the Vertex connection.
   - Keep `CLAUDE_CODE_ENABLE_AUTO_MODE=1`, the `ANTHROPIC_DEFAULT_*_MODEL` defaults, and `claude --allow-dangerously-skip-permissions "$@"`.
3. **Remove** the `tmux set-environment CLAUDE_CODE_USE_VERTEX` lines added in the earlier popup fix — obsolete (cv no longer uses that var) and the cause of the statusline `$`-leak into subscription panes.

The litellm-tracker directory path is referenced as a constant in `cv` (it lives at `~/projects/gamuda/litellm-tracker` deployed, or wherever `ov`/the user runs compose — resolve the actual deployed path during implementation).

### 3. Rotate `LITELLM_MASTER_KEY`

The key leaked into a session transcript. Regenerate it, update the encrypted env (`litellm-tracker/encrypted_dot_env.age` via chezmoi age), restart the proxy so it loads the new key, and confirm `cv` (which reads `$LITELLM_MASTER_KEY` from `dot_zshenv`) authenticates. Local-only key, but rotate as hygiene since `cv` now depends on it.

### 4. Verification (a real session)

- `cv -p "say hi"` (or interactive) succeeds through the proxy.
- A turn that uses Haiku (background) does not 404.
- Prompt caching hits across turns (`/spend/logs` or response usage shows `cache_read` > 0).
- A large-context request (>200k tokens) succeeds, confirming 1M is active (not truncated at 200k).
- `/spend/logs` shows new Claude entries with non-zero `spend`.

## Consequences

- **Statusline `$` segment and `prefix+u` cost popup stop working between A and B** — both gate on `CLAUDE_CODE_USE_VERTEX`, which `cv` no longer sets. Interim, `prefix+u` shows subscription rate-limit bars. Project B reintroduces cost via `/spend` with a proper, non-leaking signal.
- `cv` now hard-depends on the LiteLLM proxy + OrbStack being available (mitigated by the auto-start guard; no native fallback by design).

## Files touched

- `private_projects/private_gamuda/litellm-tracker/config.yaml` — model aliases.
- `private_projects/private_gamuda/litellm-tracker/encrypted_dot_env.age` — rotated key.
- `dot_config/zsh/functions/cv` — rewritten launcher.

## Testing

Launcher + live-proxy behavior is integration-verified (§4), not unit-tested. The one unit-testable unit is the proxy-guard decision (health-check → start-or-abort); factor it so its branching can be exercised with a stubbed health command, if practical.

## Risks / open items

- **On-wire model string** (`[1m]` literal vs plain + beta) — resolved by inspecting the proxy debug log during implementation; aliases cover both.
- **1M true activation** through LiteLLM — verified only at "not rejected"; §4 includes a real large-context check. If 1M does not actually engage, fall back to plain model names and accept 200k, or escalate.
- **Key rotation** touches encrypted secrets and the running container — sequence carefully (rotate → restart → verify) so `cv` isn't left unable to auth.
