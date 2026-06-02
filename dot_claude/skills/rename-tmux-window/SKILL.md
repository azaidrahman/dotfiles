---
name: rename-tmux-window
description: Use when the user asks to rename the current tmux window, retitle the window, set or update the window name, or name the window after what we're working on
---

# Rename tmux Window

Rename the tmux window this Claude session is running in. Works only inside tmux
(`$TMUX` set) — if not in tmux, say so and stop.

## 1. Decide the name

- **If the user gave a name** (skill argument or in their message): use it verbatim, trimmed.
- **Otherwise**: summarize what this session is currently working on into a short
  **2–4 word, lowercase, kebab-case** title (e.g. `tmux-window-shortcuts`,
  `auth-token-refresh`). No punctuation, no trailing/leading hyphens.

Keep it terse — it's a tab label, not a sentence.

## 2. Apply it (preserves the Claude status glyph)

A status hook may prefix a glyph (`●`/`⚠`/`⏸`/`✓`) to the window name. Keep it by
storing the base name in `@claude_base` and re-rendering any current glyph:

```bash
NAME="<the name from step 1>"
WID=$(tmux display-message -p '#{window_id}')
CUR=$(tmux display-message -p '#{window_name}')
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
