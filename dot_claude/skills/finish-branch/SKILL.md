---
name: finish-branch
description: Use when done with a branch and closing it out — "finish this branch", "finish GTI-273", "wrap up this ticket", "I'm done here, clean up", "mark it done and delete the branch". Verifies nothing is lost, confirms the work landed in the base branch, deletes the branch and its worktree, and — only if the branch name carries a Jira key — transitions that ticket to Done. Not for a repo-wide sweep of stale branches (branch-audit) or a whole-session multi-repo cleanup (wrap-session).
---

# Finish Branch

Safely close a branch: verify the objective is done, confirm nothing is lost, close the ticket if there is one, then delete.

**The branch is the unit of work; the ticket is optional.** A branch with no Jira key closes by exactly the same path, minus Step 3. Never block a close on a missing ticket, and never invent a key to fill the gap.

## Base branch

Every step reads `base:` from the preflight report. Do not hardcode it. The script prefers `develop` where that branch exists — the gitflow standard — and falls back to `origin/HEAD`, then `main`.

A repo that keeps a `develop` branch but no longer merges into it is a policy decision that git does not record, so that repo states it once and every later run reads it:

```bash
git config finishBranch.base main     # e.g. gtech-atlas, which retired develop on 2026-08-05
```

If the reported `base` looks wrong for the repo, set that config rather than passing an argument each time or editing the script.

## Preflight (scripted)

Run the read-only precheck - it gathers every fact this skill needs (clean tree,
current branch, base, commits not in base, stash, remote existence) in one report
so you don't hand-type them:

```bash
~/.claude/skills/finish-branch/finish-branch-precheck.sh
```

Act on the exit code:

| Exit | Meaning |
|------|---------|
| `2`  | Hard stop - reason on stdout (not a repo / detached / on base / **dirty tree**). Relay it and stop. |
| `0`  | Report printed. Read `base`, `unmerged_count`, `stash_count`, `remote_exists`, `ticket`, `worktree`, and the commit listing, then continue to Step 1. |

`ticket: none` and `worktree: none` are normal, not failures — they just mean Step 3 and the
worktree half of Step 4 do not apply.

The report replaces the inline `git status` / `git log develop..HEAD` / `git stash list`
/ `git ls-remote` commands below - don't re-run them; use its values. It mutates nothing;
all deletes stay gated behind your confirmation in Steps 3-4.

## Step 1 — Verify "Done"ness

The commits-unique-to-branch and stash facts already came from the preflight report
(`unmerged_count` + listing, `stash_count`). For plans, additionally run:

```bash
ls docs/superpowers/plans/ 2>/dev/null # any plans to check?
```

### 1a — Summarize the objective

Read the branch name and commits. Summarize in one sentence what this branch was supposed to accomplish.

### 1b — Check plans

If `docs/superpowers/plans/` exists, scan plan files for ones related to this branch's work (match by branch name, feature name, or task keywords from commits). For each matching plan:

- Are all checkboxes checked (`- [x]`)?
- Does a `Status: COMPLETED` line exist?

Report:

```
Plans checked: 2
  ✅ docs/superpowers/plans/feat-x.md — COMPLETED
  ⚠️  docs/superpowers/plans/feat-y.md — 2 tasks still open
```

### 1c — Check for stashed work

If `git stash list` returns anything, warn:

```
⚠️  You have stashed changes. Are these related to this branch?
```

### 1d — Confirm with the user

Show the objective summary + plan status + any stash warnings, then ask:

**"Based on the above, is this objective complete?"**

Do not proceed unless the user says yes. If plans show open tasks, name them explicitly before asking.

## Step 2 — Check What Would Be Lost

Use the preflight's `unmerged_count` (no need to re-run `git log`).

If `unmerged_count: 0` → the branch has **landed**: every commit is contained in `base`. Safe to close.

If it is **> 0** → those commits are NOT in `base`. Show the listing from the report:

```
⚠️  These commits are not in <base>:
  abc1234 feat: add X
  def5678 fix: correct Y
```

Ask the user: **"These commits aren't in `<base>` yet. Do you want to sync first, or are these already in a merged PR?"**

- If they want to sync: run the `sync-branches` skill first, then return here.
- If they confirm it's already in a merged PR: proceed, but say so explicitly. Squash and rebase merges land under new SHAs, so a genuinely merged branch can still read as unmerged here.
- If unsure: **stop**. Do not delete. Tell the user to verify.

Landed is the gate for both Step 3 and Step 4. An unlanded branch closes neither the ticket nor itself.

## Step 3 — Close the ticket (only if `ticket:` is a key)

If the preflight reported `ticket: none`, skip this whole step in silence — a branch with no ticket is normal, not a defect. Otherwise, close the ticket **before** deleting anything: if the transition fails you still hold the branch as evidence.

Read the live transitions first — status names and ids differ per board, so a hardcoded `Done` breaks silently:

```
mcp__claude_ai_Atlassian__getAccessibleAtlassianResources          # cloudId, once
mcp__claude_ai_Atlassian__getJiraIssue(cloudId, "<KEY>", fields=["summary","status"])
mcp__claude_ai_Atlassian__getTransitionsForJiraIssue(cloudId, "<KEY>")
mcp__claude_ai_Atlassian__transitionJiraIssue(cloudId, "<KEY>", transition={"id": "<id>"})
```

Load the tools with `ToolSearch` if they are not resolved yet.

| Situation | Do |
|---|---|
| A Done-category transition is available | Take it, then add one closing comment with `addCommentToJiraIssue`: the merge commit or PR link, and the branch that carried it. |
| Only an intermediate transition exists (`In Review` → `Done`) | Take the shortest path, one transition at a time. |
| The ticket is already Done | Skip the transition, say so, continue. |
| Atlassian MCP unavailable | Say which key needs a manual close, then continue to Step 4. A missing Jira never blocks the branch delete. |

## Step 4 — Delete the branch

Only proceed after Steps 1 and 2 are both confirmed. Use the `base` from the preflight report.

```bash
git switch "$BASE"
git pull --ff-only origin "$BASE"
git branch -d <branch>            # safe delete — refuses if unmerged
```

If `git branch -d` refuses (branch not fully merged per git's check), show the warning to the user and ask for explicit confirmation before using `-D`. Never silently force-delete.

**If the preflight reported a `worktree:` path**, the branch was opened by [[start-ticket]] and lives outside this checkout. Remove the worktree first — you cannot switch away from a branch that a worktree holds:

```bash
git worktree remove <path>        # refuses if dirty — that is correct, do not --force
git branch -d <branch>
git worktree prune
```

A refusal means uncommitted work. Stop and surface it; never `--force` past it.

If a tmux session from [[start-ticket]] is still live for that worktree, kill it after the worktree is gone: `tmux kill-session -t "<NAME>"`.

## Step 5 — Clean Up Remote (Optional)

The preflight already reported `remote_exists`. If it was `yes`, ask:
**"Delete the remote branch too?"**

If yes:
```bash
git push origin --delete <branch>
```

## Step 6 — Confirm Final State

```bash
git log --oneline -5              # show where the base branch is now
git branch                        # confirm branch is gone
```

Report one line per thing you closed, and name anything you deliberately left alone:

```
Branch   : feat/GTI-273-project-nova — landed in main, deleted (local + remote)
Worktree : .worktrees/GTI-273-project-nova — removed
Ticket   : GTI-273 — In Review → Done, comment added
Now on   : main @ abc1234
```

## Do NOT

- Delete branch without user confirming the objective is done
- Use `git branch -D` without explicit user confirmation of unmerged commits
- Silently skip the "what would be lost" check
- Force push anything
- Proceed past any dirty working tree
- Transition a ticket whose branch has not landed
- Invent a ticket key when the branch name has none — a ticketless branch closes fine

## See also

- [[start-ticket]] — the opening bookend; creates the branch, worktree, and tmux session this skill tears down.
- [[branch-audit]] — when the user wants a sweep of *all* stale branches rather than a close-out of the branch they are standing on.
- [[wrap-session]] — the whole-session cleanup; it commits loose work across every repo, then calls this skill per finished branch.
- [[bitbucket-pr]] — when Step 2 finds unlanded work that still needs a PR.
