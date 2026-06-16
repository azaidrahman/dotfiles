---
name: branch-pane
description: Use when — inside tmux — the user wants to fork the current Claude conversation into a new pane. Triggers like "branch this into a pane", "fork this chat into a side pane", "open a fork of this session", "branch this off".
---

# Branch the conversation into a new pane

Forks the **current Claude conversation** into a new tmux pane. Same working
directory, same git branch — only the *session* is forked. This is the
`/branch` built-in (conversation fork) opened side-by-side instead of in place.

Your current pane stays attached to the **original** session, untouched — you
never have to switch back. The new pane gets the fork.

## How to run it

Just run the script — it does everything deterministically:

```bash
bash "$CLAUDE_PLUGIN_ROOT/branch-pane.sh"      # horizontal (side-by-side) split
bash "$CLAUDE_PLUGIN_ROOT/branch-pane.sh" v    # vertical (below) split
```

If `$CLAUDE_PLUGIN_ROOT` isn't set, use the absolute path
`~/.claude/skills/branch-pane/branch-pane.sh`.

Then relay the script's output (forked session id, new pane id) to the user.

## What the script does

1. Aborts if not inside tmux (`$TMUX` unset).
2. Reads the current session id from `$CLAUDE_CODE_SESSION_ID` (falls back to the
   newest session `.jsonl` for `$PWD` if that's somehow unset).
3. Splits a new pane unfocused (`-d`) in the same directory.
4. Sends `claude --resume <id> --fork-session` into it — forking the conversation
   into a fresh session that lives in the new pane.
5. Titles the pane `fork:<short-id>` and reports.

For ticket-anchored work in an isolated worktree (Jira key, proper base branch),
use [[start-ticket]] instead — that forks the *workspace*, this forks the *chat*.
