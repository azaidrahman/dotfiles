---
name: sync-branches
description: Use when the user asks to sync, promote, or push their feature branch up through other branches - supports partial sync (e.g. feat->develop only) or full sync (feat->develop->main)
---

# Sync Branches

Sync current feature branch up through the branch hierarchy. Supports flexible targets:

- `/sync-branches` or `/sync-branches develop` — sync feat -> develop only
- `/sync-branches main` — full sync: feat -> develop -> main
- `/sync-branches <branch>` — sync feat -> that specific branch

**Default target is `develop`** unless the user explicitly asks for main or says "full sync" / "all the way".

## Prerequisites

Before starting, run in parallel:
- `git status` - must be clean (no uncommitted changes)
- `git branch --show-current` - must be on a feature branch (not develop or main)

**If working tree is dirty:** Stop. Tell the user to commit or stash first. Do not proceed.

**If on develop or main:** Stop. Tell the user to switch to their feature branch first.

## Workflow

### 1. Push Feature Branch

```bash
git push origin <feat-branch>
```

Report success to user.

### 2. Sync to Target Branch

For each branch in the chain (e.g. develop, then main if requested), merge sequentially:

```bash
git checkout <target>
git pull --ff-only origin <target>
git merge --ff-only <source>
git push origin <target>
```

Where `<source>` is the previous branch in the chain (feat-branch for develop, develop for main).

**If fast-forward is not possible:** Return to the feature branch and tell the user the branches have diverged — they need to rebase their feature branch on top of `<target>` first. Do not attempt to resolve divergence automatically.

### 3. Confirmation Before Main

**If the target includes main**, ask the user for confirmation before merging. Show them what commits will be merged:

```bash
git log --oneline develop..main   # commits on main not in develop
git log --oneline main..develop   # commits on develop not in main
```

Only proceed after user confirms.

### 4. Return to Feature Branch

```bash
git checkout <feat-branch>
```

Report final status: which branches were synced and pushed.

## Do NOT

- Proceed with dirty working tree
- Force push any branch
- Resolve merge conflicts automatically
- Skip the confirmation before pushing to main
- Use `--no-verify` on any push
