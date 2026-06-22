# tmux-native Claude session fork (`|` / `_`)

**Date:** 2026-06-22
**Status:** Approved, pending implementation

## Goal

Replace the `branch-pane` Claude skill with two tmux key bindings that fork the
Claude conversation running in the *currently selected pane* into a new pane —
instantly, without consuming a Claude turn. The skill required asking Claude to
run a script; the binding does it directly from tmux.

## Bindings

Added to `dot_tmux/conf.d/keys.conf`, alongside the existing split binds
(`\` = `split-window -h`, `-` = `split-window -v`):

```
bind | run-shell "~/.tmux/scripts/fork-claude-pane.sh '#{pane_id}' '#{pane_current_path}' '#{pane_tty}' h"
bind _ run-shell "~/.tmux/scripts/fork-claude-pane.sh '#{pane_id}' '#{pane_current_path}' '#{pane_tty}' v"
```

Mnemonic: **shift the split key to fork the session instead of just splitting.**
`|` (shift-`\`) forks side-by-side; `_` (shift-`-`) forks below. Both keys
verified free — no existing config bind, absent from the live prefix table.

## Script: `dot_tmux/scripts/executable_fork-claude-pane.sh`

Args: `pane_id cwd tty {h|v}` (passed via tmux format expansion, matching the
`claude-diff-review.sh` / `pane-md-preview.sh` arg-passing convention).

1. **Gate to Claude panes.** Reuse the `is-claude-pane.sh` check on `$tty`
   (`ps -t <tty> -o command= | grep -q '[c]laude'`). If no `claude` process,
   `tmux display-message "fork: not a Claude pane"` and exit 0.
2. **Resolve the session id.** Triggered externally, so `$CLAUDE_CODE_SESSION_ID`
   is unavailable. Derive from cwd: project dir = `$cwd` with `/` and `.`
   translated to `-`, then newest `*.jsonl` by mtime under
   `~/.claude/projects/<proj>/`. The active session's file is the one currently
   being written, so newest-mtime is reliable. If none found,
   `display-message "fork: no session for this dir"` and exit 0.
3. **Split + fork.** `tmux split-window -h|-v -d -c "$cwd" -t "$pane_id"`, capture
   the new `#{pane_id}`, `send-keys` `claude --resume <id> --fork-session` + Enter,
   and `select-pane -T "fork:<short-id>"`.
4. **Feedback.** `tmux display-message "forked <short-id> → <new pane>"` — no
   Claude is relaying output now, so the binding reports for itself.

## Cleanup

Delete `~/.claude/skills/branch-pane/` (SKILL.md + `branch-pane.sh`) — the bindings
fully replace it. The skill's pointer/registration, if any, is removed too.

## Out of scope

- Worktree-isolated, ticket-anchored forks remain the job of `start-ticket`.
- No change to the plain `\` / `-` split binds.
