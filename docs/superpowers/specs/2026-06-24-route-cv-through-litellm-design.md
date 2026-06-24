# Project A: Route `cv` (Claude Code) through LiteLLM on onyx

**Date:** 2026-06-24
**Status:** Approved design, pending implementation
**Relation:** Foundation for Project B (cost popup reads LiteLLM `/spend`). B is blocked on this.

## Problem

`cv` runs Claude Code against Vertex natively (`CLAUDE_CODE_USE_VERTEX=1`, direct to Vertex). The LiteLLM proxy (`litellm-tracker`) therefore never sees Claude Code traffic and has no cost data for it. Goal: make LiteLLM the single gateway so every Claude Code request is logged — and make this work from **both** machines.

## Topology

- **onyx** — always-on work laptop. Hosts the LiteLLM proxy (OrbStack docker-compose + Postgres), authenticating to Vertex via onyx's `~/.config/gcloud` ADC. This is where the proxy and its config/`.env` live and run.
- **aqua** — second laptop, a client. Runs `cv` too, routing to onyx's proxy over **Tailscale**.
- Both are in the same tailnet (`tail5d740c.ts.net`). onyx Tailscale IP `100.86.30.80`, MagicDNS FQDN `onyx.tail5d740c.ts.net`. aqua↔onyx SSH works via Tailscale (`ProxyCommand tailscale nc`).

`cv` is one chezmoi-managed function deployed to both machines; it must behave correctly on each.

## Goal

`cv` (on onyx or aqua) launches Claude Code routed through onyx's LiteLLM proxy with full feature fidelity (prompt caching, 1M context, extended thinking, tool use, streaming) and Haiku available, so all Claude Code requests are logged in LiteLLM's spend DB.

## Non-goals

- Cost popup / statusline cost display — **Project B**.
- A native-Vertex fallback — native path is **replaced** (user decision).

## Feasibility (verified via spike, 2026-06-24, on onyx)

Against the proxy `/v1/messages` on `claude-opus-4-8`:
- **Prompt caching** forwarded faithfully (write `cache_creation=16204` → repeat `cache_read=16204`, incl. 5m/1h split).
- **Extended thinking** (`adaptive`) → `["thinking","text"]`, no error.
- **Tool use** → `stop_reason=tool_use`.
- **Streaming** → SSE delivered.
- **Spend logging** → `/spend/logs` records per-request `spend`/`model`/`total_tokens` (cache split is `null` — Project B's concern).
- **1M:** model name `claude-opus-4-8[1m]` → 400 (unregistered); plain name + `anthropic-beta: context-1m-2025-08-07` → 200 (LiteLLM forwards the beta).
- **Reachability:** onyx→self via Tailscale **IP** `100.86.30.80:4000` works; bare `onyx` and the FQDN did *not* resolve onyx-to-self (self-resolution quirk) — informs the machine-aware base URL below.

## Design

### 1. LiteLLM config — register `cv`'s model strings

File: `litellm-tracker/config.yaml` (on onyx). Add `model_list` entries whose `model_name` matches what Claude Code sends, mapped to Vertex, 1M beta forced on `[1m]` variants:

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

Keep existing plain opus/sonnet + gemini entries. **Haiku is required** (Claude Code background calls 404 without it).

**Impl verification gate:** confirm the on-wire model string via the proxy `--detailed_debug` log; ensure a matching `model_name` exists (the `[1m]` aliases + the plain entries together cover both "literal `[1m]`" and "plain + beta header" behaviors).

### 2. Tailscale-only binding (replace `*:4000`)

File: `litellm-tracker/docker-compose.yml` (on onyx). Currently binds `4000:4000` (all interfaces). Change to bind **loopback + onyx's Tailscale IP only**, so `:4000` is never exposed on LAN/public wifi:

```yaml
    ports:
      - "127.0.0.1:4000:4000"
      - "100.86.30.80:4000:4000"   # onyx Tailscale IP (or via ${ONYX_TS_IP} from .env)
```

(Loopback keeps onyx-local `cv` simple; the Tailscale-IP binding serves aqua; nothing on `0.0.0.0`.) Prefer `${ONYX_TS_IP}` from the `.env` over a hardcoded literal if practical.

### 3. Rewrite `cv` (machine-aware)

File: `dot_config/zsh/functions/cv`.

**Base URL** (machine-aware, avoids the self-resolution quirk):
- on onyx (`hostname -s` matches `onyx*`) → `http://localhost:4000`
- else (aqua) → `http://onyx.tail5d740c.ts.net:4000` (fallback `http://100.86.30.80:4000`)

**Proxy guard:**
- Health-check `GET <base>/health/liveliness` (short timeout).
- If unhealthy **and on onyx** → `docker compose -f <litellm dir> up -d`, poll health ~20s.
- If unhealthy **and on aqua** → `ssh onyx 'cd <litellm dir> && docker compose up -d'` (over Tailscale), poll health ~20s.
- If still unhealthy (or docker/ssh unavailable) → print the start command and **return non-zero without launching claude**.

**Routing env:**
- `export ANTHROPIC_BASE_URL=<base>`
- `ANTHROPIC_AUTH_TOKEN=$LITELLM_MASTER_KEY`
- **Do not set** `CLAUDE_CODE_USE_VERTEX`, `ANTHROPIC_VERTEX_PROJECT_ID`, `CLOUD_ML_REGION`.
- Keep `CLAUDE_CODE_ENABLE_AUTO_MODE=1`, the `ANTHROPIC_DEFAULT_*_MODEL` defaults, `claude --allow-dangerously-skip-permissions "$@"`.

**Remove** the `tmux set-environment CLAUDE_CODE_USE_VERTEX` lines added in the earlier popup fix — obsolete and the cause of the statusline `$`-leak.

The litellm dir path (where compose runs on onyx) is resolved during implementation (the deployed location of `litellm-tracker`) and used as a constant in `cv`.

### 4. Rotate `LITELLM_MASTER_KEY`

Leaked into a session transcript. Regenerate, update `litellm-tracker/encrypted_dot_env.age` (chezmoi age), restart the proxy to load it, confirm `cv` (reads `$LITELLM_MASTER_KEY` from `dot_zshenv`, shared to both machines) authenticates. Sequence: rotate → restart → verify, so `cv` is never left unable to auth.

### 5. Verification

- **onyx:** `cv -p "say hi"` works through the proxy; a Haiku-using turn does not 404; caching hits across turns; a >200k-token request engages 1M; `/spend/logs` shows new Claude entries with `spend>0`.
- **aqua:** same, reaching onyx over Tailscale; proxy-guard SSH-start path works when onyx's proxy is down.

## Consequences

- **Between A and B, the statusline `$` segment and `prefix+u` cost popup stop working** (both gate on `CLAUDE_CODE_USE_VERTEX`, no longer set). Interim `prefix+u` shows subscription rate-limit bars; Project B reintroduces cost via `/spend` with a proper signal.
- `cv` now hard-depends on onyx's proxy + Tailscale (mitigated by the auto-start / SSH-start guard; no native fallback by design).

## Files touched

- `litellm-tracker/config.yaml` — model aliases.
- `litellm-tracker/docker-compose.yml` — Tailscale-only binding.
- `litellm-tracker/encrypted_dot_env.age` — rotated key (+ `ONYX_TS_IP` if used).
- `dot_config/zsh/functions/cv` — rewritten launcher.

## Testing

Launcher + live-proxy behavior is integration-verified (§5), not unit-tested. Factor the proxy-guard decision (health → local-start / ssh-start / abort, branching on host) so its logic can be exercised with a stubbed health/ssh command if practical.

## Risks / open items

- **Deployed litellm dir path** on onyx — resolve before writing the guard.
- **onyx Tailscale IP** hardcoded in compose binding — stable per device but changes if the node is re-added; prefer `${ONYX_TS_IP}` from `.env`.
- **On-wire model string** (`[1m]` vs plain+beta) — resolved via proxy debug log; aliases cover both.
- **1M true activation** — verified "not rejected"; §5 includes a real large-context check.
- **MagicDNS FQDN from aqua** — assumed to resolve (normal remote case); IP fallback if not.
- **Key rotation** touches encrypted secrets + running container — sequence carefully.
