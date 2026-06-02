---
name: branch-pane
description: Use when — inside tmux — the user wants to fork the current branch into a new worktree opened in a new pane running claude. Triggers like "open this in a new branch/pane", "fork this into a worktree", "branch this off", "spin up a side pane".
---

# Branch into a new pane

Forks the **current branch** into a fresh worktree + branch and opens it in a new
tmux pane running `claude`. Branch name is `<current-branch>-<random id>` (e.g.
`main-4821`) — no topic-naming, no thinking required. Your current pane and checkout
are left untouched.

The `/branch` built-in forks the *conversation*; this forks the *workspace*.

## How to run it

Just run the script — it does everything deterministically:

```bash
bash "$CLAUDE_PLUGIN_ROOT/branch-pane.sh"      # horizontal (side-by-side) split
bash "$CLAUDE_PLUGIN_ROOT/branch-pane.sh" v    # vertical (below) split
```

If `$CLAUDE_PLUGIN_ROOT` isn't set, use the absolute path
`~/.claude/skills/branch-pane/branch-pane.sh`.

Then relay the script's output (branch, worktree path, new pane id) to the user. Don't
re-derive a branch name or open the pane yourself — the script owns all of that.

## What the script does

1. Aborts if not inside tmux (`$TMUX` unset).
2. `BRANCH=<current-branch>-<4-digit random>`, worktree at `.worktrees/<branch>` (slashes flattened).
3. Aborts (never forces) if that branch or path already exists.
4. `git worktree add -b` off current HEAD — no fetch, no push.
5. Splits a new pane unfocused (`-d`), `cd`'d into the worktree, and sends `claude`.

## Cleaning up forks

`branch-pane-clean.sh` removes forks that are **safe** to drop — clean working tree and
no commits unique to the branch. Dirty or unmerged forks are kept and reported.

```bash
bash "$CLAUDE_PLUGIN_ROOT/branch-pane-clean.sh"            # sweep all .worktrees/* forks
bash "$CLAUDE_PLUGIN_ROOT/branch-pane-clean.sh" main-2097  # one specific fork
```

(Same `~/.claude/skills/branch-pane/` fallback path if `$CLAUDE_PLUGIN_ROOT` is unset.)

For ticket-anchored work (Jira key, proper base branch), use [[start-ticket]] instead.
