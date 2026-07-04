# Swap the prefix+e diff-review popup from codediff to hunk

**Date:** 2026-07-04
**Status:** approved

## Problem

`prefix+e` opens a tmux popup running a standalone `nvim -u claude-diff-review-init.lua`
that loads codediff.nvim, lets the user collect hunk refs in the UI, and pastes a
text summary back into the origin Claude pane. This is ~737 lines of custom Lua
wiring plus a launcher, a Claude-pane gate, and a codediff lazy spec.

`hunk` (hunk.dev, already installed via Brewfile) is purpose-built for exactly this
workflow: a review-first terminal diff viewer for agent-authored changesets. It
auto-reloads as the working tree changes and exposes a live-session daemon that a
coding agent drives via `hunk session ...` — replacing the manual collect-and-paste
mechanism with direct agent inspection/navigation/commenting.

## Goal

Preserve the `prefix+e` muscle memory — "from my current pwd, see all the changes
in this repo and review them" — but back it with `hunk diff` instead of nvim/codediff.

## Design

### Launcher: `dot_tmux/scripts/executable_claude-diff-review.sh`

Rewritten as plain bash (no nvim). Args: `1 = pane_current_path` (the `pane_id`
paste-back arg is dropped).

Flow:
1. Determine target repo. If `$cwd` is inside a git work tree **with changes**
   (tracked or untracked), that's the target.
2. Otherwise (clean repo, or not a repo) fall back to a `zoxide query --list | fzf`
   repo picker — same pattern as `md-pick.sh`. Falls back to a numbered menu when
   fzf is absent. Cancelling exits cleanly (no empty popup, no dead end).
3. `tmux display-popup -E -w 90% -h 90% -d "$target" -- hunk diff`

Hunk auto-reloads on working-tree changes, so the popup stays live while Claude
edits in another pane — no manual reload keybinding needed.

### keys.conf

Line 135 binding drops `#{pane_id}` (no paste-back):

```
bind e run-shell "~/.tmux/scripts/claude-diff-review.sh '#{pane_current_path}'"
```

Comment above it updated to describe the hunk review flow.

### Claude-side skill

Add a chezmoi-managed symlink so every Claude Code session on this machine gets
hunk's bundled review skill:

```
dot_claude/skills/hunk-review/symlink_SKILL.md
  -> /opt/homebrew/opt/hunk/libexec/skills/hunk-review/SKILL.md
```

`/opt/homebrew/opt/hunk` is homebrew's stable version-independent path (survives
`brew upgrade hunk`). This is exactly what hunk's own docs recommend: "Load or
symlink that file in your coding agent to keep it in sync across Hunk upgrades."

With the skill present, Claude drives the live `hunk diff` session via
`hunk session review/navigate/comment ...` against the local loopback daemon —
inspecting the diff, steering the user's view, and reading/adding inline comments.

## What gets deleted

Superseded by hunk's native session + comment system:
- `dot_tmux/scripts/claude-diff-review-init.lua` (737 lines)
- `dot_tmux/scripts/executable_is-claude-pane.sh` (only the old paste-back gate used it — verified no other references)
- `dot_config/nvim/lua/zaid/plugins/codediff.lua` (codediff.nvim was only for this popup; diffview.nvim stays for neogit)

## Out of scope

- No replacement for the old collect-hunks-and-paste-to-Claude button. Hunk's
  comment system + agent skill covers the review-collaboration need differently
  (live, not paste-based).
- Old design docs under `docs/superpowers/` stay as history.

## Verification

- `prefix+e` in a repo with working-tree changes → hunk opens showing those changes.
- `prefix+e` in a clean repo / non-repo → zoxide picker; choosing a repo opens hunk there; cancelling exits cleanly.
- A fresh `claude` session lists `hunk-review` among its skills.
- `brew upgrade hunk` (simulated by version bump) keeps the symlink valid.
