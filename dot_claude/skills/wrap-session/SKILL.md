---
name: wrap-session
description: Use at the end of a work session to clean up and close out — "wrap up this session", "clean up and commit everything I touched", "sync everything", "close out the done branches", "finish up here". Audits everything the session touched across all repos and chezmoi, gets it committed/pushed, and closes finished branches/PRs.
---

# Wrap Session

End-of-session orchestrator. Takes stock of everything this session touched, gets it
clean, and closes it out — committing, pushing, finishing done branches, merging PRs.

**This skill orchestrates; it does not reimplement.** Its only original logic is the
cross-context inventory and the untracked-in-managed detection. Everything else is
**delegated** to the purpose-built skill for that context (see the handler table).
When a handler skill exists, invoke it — never hand-roll its commit/push/merge steps.

## When to use

- "wrap up", "clean up this session", "sync everything I touched", "close out"
- End of any session before you walk away — to leave repos clean and done branches gone

## When NOT to use

- Mid-session: you're still working. This is a closing ritual.
- A single known commit in one repo → just use `commit` directly.

## Workflow

Run the phases in order. Each phase gates the next.

### 1. Inventory — what did this session touch?

Derive this from the **conversation transcript**, not from the user re-describing it.
List every file you created or edited via Write/Edit/NotebookEdit this session, plus
any path you committed to. Resolve each to its owning context:

- A git repo → its repo root (`git -C <dir> rev-parse --show-toplevel`).
- A chezmoi-managed path → the chezmoi context (`chezmoi source-path <file>` succeeds).

Always include the current working directory's repo. Dedupe into a location list.

While inventorying, also flag **session scratch** — throwaway files you created only to
get the work done, not as deliverables: one-off scripts, `/tmp` files, debug dumps,
`*.bak`/`*.orig`, captured command output, sample payloads, exploratory notebooks. These
are tracked separately from the deliverable set and are **removed** in Phase 3, not
committed. When unsure whether a file is scratch or a deliverable, treat it as a
deliverable and ask.

### 2. Cleanliness scan — per location

For each location, detect dirt three ways (the third is the one plain `git status` misses):

```bash
# tracked-but-dirty (project repos AND the chezmoi source repo)
git -C <repo> status --short

# managed targets that diverged from source (edited outside chezmoi)
chezmoi status
chezmoi diff --no-pager

# untracked files sitting in a managed dir that chezmoi doesn't know about yet
#   compare what chezmoi manages against what's actually on disk in that dir
comm -13 <(chezmoi managed --path-style absolute | sort) <(find <managed-dir> -type f | sort)
```

Present a **per-location report**: location → files → kind
(`tracked-dirty` / `diverged-target` / `untracked-in-managed`).

**If every location is clean, say so and skip to Phase 4** (branch lifecycle may still
have work even when the tree is clean).

### 3. Validate, then dispatch via the handler table

First a secret/scope pass over the dirty set — reuse the red flags below. Then present
the plan and **get the user's confirmation** before any write.

Match each dirty location to a handler and invoke it:

| Context match | Handler |
|---|---|
| chezmoi-managed change (diverged-target or untracked-in-managed) | invoke **`chezmoi-sync`** — it owns the `chezmoi add`, secret scan, commit, and push. Do NOT `chezmoi add` or commit the source repo yourself. |
| git project repo, tracked-dirty | invoke **`commit`** (authors a message in house style; branch-name-ticket aware), then `git -C <repo> push` if it has an upstream |
| session scratch (temp/throwaway file from Phase 1) | **remove it** — `rm` the file (and `/tmp` artifacts), or `git -C <repo> clean`/`checkout` if it's untracked/uncommitted in a repo. Confirm the scratch list with the user first; never delete a file you committed earlier this session or one the user named as a deliverable. |
| *(future contexts)* | *(add a row — a folder-specific finish routine, etc.)* |

Remove scratch **before** committing the deliverable set, so throwaway files never slip
into a commit.

The handler table is the extension point. New end-of-session behaviors are new rows,
not new skills.

### 4. Branch lifecycle — close out finished branches & PRs

Per repo that has branches, **delegate**:

1. Invoke **`branch-audit`** → it classifies local/remote branches and worktrees by
   merge status into main/develop and cross-references each branch's Jira key
   (Done / In Review / Active), and recommends only safe deletions.
2. For each branch it flags as **done** (merged, or ticket Done *and* verified merged):
   - If it has an open PR to merge → invoke **`commit-push-pr`** (GitHub) or
     **`bitbucket-pr`** (Bitbucket repos — `gh` does not work there).
   - Then invoke **`finish-branch`** to merge-verify, switch back to the base branch,
     delete the branch + its worktree, **and transition the branch's Jira ticket to Done**.
     Do not close tickets yourself — `finish-branch` reads the live transitions per board
     and gates the close on the work having landed. A branch with no ticket key closes
     the same way, minus that step.

**Jira "Done" does NOT mean the branch is merged.** Squash/rebase merges land under new
SHAs, so a Done ticket can still have a local branch whose commits aren't in the base.
Verify with `git branch --merged <base>` or `git cherry -v <base> <branch>` before
deleting. If Jira says Done but git disagrees, **stop and flag it** — never `-D`.

### 5. Verify

Re-run the Phase 2 scan on every touched location and confirm clean. Confirm the
session-scratch files are gone (none left on disk, none committed). Report what was
committed / pushed / merged / deleted (including scratch removed), and anything
intentionally left (mid-work branches, things you flagged).

## Red Flags — STOP and confirm

- A dirty file contains secrets, keys, tokens, or is `private_*` → stop, warn, do not commit.
- A "done" branch whose commits are **not** actually in the base branch → stop, do not delete.
- Changes outside this session's scope showing up in a repo → confirm before staging.
- Any **remote** branch deletion or **PR merge** → outward-facing; confirm per item.
- Git remote unreachable → report and stop, don't loop.
- A file you're about to delete as scratch was committed earlier this session, or the
  user called it a deliverable → stop, do not delete; it's not scratch.

## Common mistakes

- **Hand-rolling chezmoi commits** instead of invoking `chezmoi-sync` — you lose its
  target→source reconciliation and secret validation. Always delegate.
- **`git add -A` / `chezmoi add` of everything** — stage only this session's files;
  blanket-add sweeps in unrelated dirt. The handler skills enforce this; let them.
- **Skipping the untracked-in-managed scan** — new files in `~/.claude`, `~/.config`,
  etc. are invisible to `git status` and `chezmoi status`. Phase 2's `comm` catches them.
- **Trusting Jira "Done" to mean merged** — verify the commits are in the base branch first.
- **Touching mid-work branches** — only the branches `branch-audit` flags as done are in scope.
- **Asking the user to re-describe what changed** — you have the transcript; inventory from it.
- **Committing session scratch** — one-off scripts, `/tmp` dumps, and debug output are
  removed in Phase 3, not committed. Inventory them in Phase 1 so they don't ride along.
