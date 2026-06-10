---
name: rename-tmux-window
description: Use when the user asks to rename, retitle, label, or set the current tmux window name — including naming it after a Jira ticket (e.g. "rename to GTI-197", "tag this window with the ticket"), naming it after what we're working on, or any explicit window title change.
---

# Rename tmux Window

Rename the tmux window this Claude session is running in. Works only inside tmux
(`$TMUX` set) — if not in tmux, say so and stop.

## 1. Decide the name

- **If the user gave a literal name**: use it verbatim, trimmed.
- **Otherwise, find a ticket key** — check user message first, then current branch:

  ```bash
  BRANCH=$(git -C "$(tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}')" rev-parse --abbrev-ref HEAD 2>/dev/null)
  TICKET=$(printf '%s' "$BRANCH" | grep -oE '[A-Z]+-[0-9]+' | head -1)
  ```

  - **Ticket found** → fetch the Jira summary via `mcp__claude_ai_Atlassian__getJiraIssue` (fields: `["summary"]`), then squeeze it (see below). Format: `<KEY> <label>` (space-separated, total ≤ 25 chars).
  - **No ticket** → summarize the session into a short **2–4 word, lowercase, kebab-case** title (e.g. `tmux-window-shortcuts`).

### Label-squeezing rules (ticket names only)

Apply in order to the raw Jira summary:

1. Lowercase; strip punctuation and em/en dashes.
2. Drop fillers: `the a an of for to on in and with into from by`.
3. Drop ceremony verbs at the start: `create make setup set add build write do enable get give`.
4. Drop generic nouns when something more specific follows: `request permission access task ticket project`.
5. Keep first 2–3 *meaningful* tokens; join with `-`.
6. Hard cap: 15 chars for the label — if longer, drop the last token.

### Examples

| Ticket | Summary | Window name |
|--------|---------|-------------|
| GTI-197 | Make a jira optimizer to set timers for all tickets | `GTI-197 jira-optimizer` |
| GTI-274 | Custom domain mapping | `GTI-274 domain-mapping` |
| GTI-238 | GCP Artifact Registry — Create Docker repository for gt-odin CI/CD | `GTI-238 artifact-docker` |
| GTI-243 | Enable Claude model | `GTI-243 claude-model` |
| GTI-262 | Access to secrets for the service account | `GTI-262 secrets-sa` |

## 2. Apply (preserves the glyph, claims the name)

`~/.claude/hooks/notify-tmux.sh` manages window names: it prefixes a status glyph
(`●`/`⚠`/`⏸`/`✓`) stored against `@claude_base`, and on each `stop` it auto-names the
window from Claude Code's conversation topic — **unless `@claude_autoname_done` is set.**
So you must do two things or the auto-namer will clobber your name on the next stop:

1. Store the base name in `@claude_base` (the glyph hook re-renders from this).
2. Set `@claude_autoname_done 1` to claim the window — this tells `notify-tmux.sh`
   the window is named, so its topic-based capture stands down.

**Always target `$TMUX_PANE`**, not the bare query. `tmux display-message -p '...'`
reports the *attached client's active window* — whichever the user is looking at right now —
not the window this Claude pane lives in. `$TMUX_PANE` is set by tmux to this process's own
pane, so `-t "$TMUX_PANE"` always resolves to Claude's window regardless of user focus.

```bash
NAME="<the name from step 1>"
WID=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
CUR=$(tmux display-message -p -t "$TMUX_PANE" '#{window_name}')
GLYPH=$(printf '%s' "$CUR" | grep -oE '^[●⚠⏸✓]' || true)
tmux set-option -w -t "$WID" @claude_base "$NAME"
tmux set-option -w -t "$WID" @claude_autoname_done 1
tmux rename-window -t "$WID" "${GLYPH:+$GLYPH }$NAME"
```

## 3. Confirm

Report the new name back (e.g. `Renamed window → ● GTI-197 jira-optimizer`).

## Common mistakes

- **Skipping `@claude_base`** — the glyph hook reverts the name on the next status event without it.
- **Skipping `@claude_autoname_done`** — `notify-tmux.sh` overwrites your name with the conversation-topic name on the next `stop` if this isn't set.
- **Using `-t` with a bare `display-message` query** — targets the user's current window, not Claude's pane; use `$TMUX_PANE`.
- **Using raw Jira summary verbatim** — 60-char summaries defeat status-bar readability; always squeeze.
- **Keeping ceremony verbs** (`create`, `make`, `setup`) — strip them; they appear in 80% of summaries and carry no signal.
