---
name: finish-branch
description: Use when done with a feature branch and want to verify nothing is lost, ensure work is merged into develop/main, switch back to develop, and delete the branch safely.
---

# Finish Branch

Safely close a feature branch: verify the objective is done, confirm nothing is lost, sync to develop, then delete.

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
| `0`  | Report printed. Read `unmerged_count`, `stash_count`, `remote_exists`, and the commit listing, then continue to Step 1. |

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

If `unmerged_count: 0` → branch is fully merged into the base. Safe to delete.

If it is **> 0** → those commits are NOT in the base. Show the listing from the report:

```
⚠️  These commits are not in develop:
  abc1234 feat: add X
  def5678 fix: correct Y
```

Ask the user: **"These commits aren't in develop yet. Do you want to sync first, or are these already in main/a PR?"**

- If they want to sync: run the `sync-branches` skill first, then return here.
- If they confirm it's already in a merged PR or main: proceed, but say so explicitly.
- If unsure: **stop**. Do not delete. Tell the user to verify.

## Step 3 — Delete the Branch

Only proceed after Step 1 and Step 2 are both confirmed.

```bash
git checkout develop
git pull --ff-only origin develop
git branch -d <branch>            # safe delete — refuses if unmerged
```

If `git branch -d` refuses (branch not fully merged per git's check), show the warning to the user and ask for explicit confirmation before using `-D`. Never silently force-delete.

## Step 4 — Clean Up Remote (Optional)

The preflight already reported `remote_exists`. If it was `yes`, ask:
**"Delete the remote branch too?"**

If yes:
```bash
git push origin --delete <branch>
```

## Step 5 — Confirm Final State

```bash
git log --oneline -5              # show where develop is now
git branch                        # confirm branch is gone
```

Report: branch deleted, now on develop at `<commit>`.

## Do NOT

- Delete branch without user confirming the objective is done
- Use `git branch -D` without explicit user confirmation of unmerged commits
- Silently skip the "what would be lost" check
- Force push anything
- Proceed past any dirty working tree
