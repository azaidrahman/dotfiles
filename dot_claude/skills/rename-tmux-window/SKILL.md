---
name: rename-tmux-window
description: Use when the user asks to rename the current tmux window, retitle the window, set or update the window name, or name the window after what we're working on
---

# Rename tmux Window

Rename the tmux window this Claude session is running in. Works only inside tmux
(`$TMUX` set) — if not in tmux, say so and stop.

## 1. Decide the name

- **If the user gave a name** (skill argument or in their message): use it verbatim, trimmed.
- **Otherwise, prioritize the Jira ticket.** Branches follow `<type>/<KEY>-<slug>`,
  so check the current branch for a ticket key (`[A-Z]+-[0-9]+`):

  ```bash
  BRANCH=$(git -C "$(tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}')" rev-parse --abbrev-ref HEAD 2>/dev/null)
  TICKET=$(printf '%s' "$BRANCH" | grep -oE '[A-Z]+-[0-9]+' | head -1)
  ```

  - **Ticket found** → lead with it, then a 1–3 word topic: `GTI-273 auth-refresh`.
  - **No ticket** → summarize what this session is working on into a short
    **2–4 word, lowercase, kebab-case** title (e.g. `tmux-window-shortcuts`).

Keep it terse — it's a tab label, not a sentence. No trailing/leading hyphens.

## 2. Apply it (preserves the Claude status glyph)

A status hook may prefix a glyph (`●`/`⚠`/`⏸`/`✓`) to the window name. Keep it by
storing the base name in `@claude_base` and re-rendering any current glyph.

**Target `$TMUX_PANE`, not the bare query.** `tmux display-message -p '...'` reports
the *attached client's active window* — whichever the user is looking at right now —
not the window this Claude pane lives in. If the user has switched away, that renames
the wrong window. `$TMUX_PANE` is the env var tmux sets to this process's own pane, so
`-t "$TMUX_PANE"` always resolves to Claude's window:

```bash
NAME="<the name from step 1>"
WID=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
CUR=$(tmux display-message -p -t "$TMUX_PANE" '#{window_name}')
GLYPH=$(printf '%s' "$CUR" | grep -oE '^[●⚠⏸✓]' || true)
tmux set-option -w -t "$WID" @claude_base "$NAME"
tmux rename-window -t "$WID" "${GLYPH:+$GLYPH }$NAME"
```

## 3. Confirm

Report the new window name back to the user (e.g. `Renamed window → ● auth-token-refresh`).

## Notes

- Setting `@claude_base` is what keeps the glyph hook from reverting the name on the
  next event — do not skip it.
- tmux window names allow spaces, but prefer kebab-case for auto-generated titles so
  they stay compact in the status bar.
