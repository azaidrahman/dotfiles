#!/usr/bin/env bash
# finish-branch-precheck.sh — read-only "what would be lost" report for closing a branch.
#
# Gathers every fact finish-branch needs before deciding to delete, in one place so the
# agent reads a consistent report instead of hand-typing five commands. Mutates NOTHING.
# The actual delete / remote-delete stay in the skill, gated behind user confirmation.
#
# Usage:  finish-branch-precheck.sh [BASE]      # BASE overrides auto-detected integration branch
# stdout: key: value report + commit/stash listings
# Exit:   0 safe to proceed to the Done-ness judgment
#         2 hard stop (not a repo / detached / on base / dirty tree) — reason on stdout
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "stop: not inside a git repo"; exit 2; }

BRANCH=$(git branch --show-current)
[ -n "$BRANCH" ] || { echo "stop: detached HEAD (no current branch)"; exit 2; }

case "$BRANCH" in
  main|master|develop) echo "stop: on base branch ($BRANCH) — nothing to close"; exit 2 ;;
esac

# Base = explicit arg, else the repo's own override, else develop, else origin/HEAD, else main.
#
# develop stays ahead of origin/HEAD because that is the gitflow standard: where a develop
# branch exists, features merge into it, while origin/HEAD points at main. Reversing the two
# would send every gitflow feature branch to the wrong base.
#
# A repo that keeps a develop branch but no longer merges into it is a policy decision, not
# something git records — gtech-atlas retired develop on 2026-08-05, yet origin/develop still
# exists and sits 0 commits ahead of main, which is identical to a freshly-merged gitflow repo.
# No heuristic can separate the two, so such a repo states it once:
#
#     git config finishBranch.base main
BASE=${1:-}
[ -n "$BASE" ] || BASE=$(git config --get finishBranch.base || true)
if [ -z "$BASE" ]; then
  if git show-ref --verify --quiet refs/remotes/origin/develop; then BASE=develop
  else
    BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)
    [ -n "$BASE" ] || { git show-ref --verify --quiet refs/remotes/origin/main && BASE=main || BASE=develop; }
  fi
fi

DIRTY=$(git status --porcelain)
echo "branch: $BRANCH"
echo "base: $BASE"
if [ -n "$DIRTY" ]; then
  echo "clean: no"
  echo "stop: working tree is dirty — commit or stash first"
  echo "--- uncommitted ---"
  printf '%s\n' "$DIRTY"
  exit 2
fi
echo "clean: yes"

# Commits on this branch not in base = what a delete would lose if unmerged.
UNMERGED=$(git log --oneline "$BASE..HEAD" 2>/dev/null || true)
UNMERGED_N=$(printf '%s' "$UNMERGED" | grep -c . || true)
echo "unmerged_count: $UNMERGED_N"

STASH=$(git stash list 2>/dev/null || true)
STASH_N=$(printf '%s' "$STASH" | grep -c . || true)
echo "stash_count: $STASH_N"

if git ls-remote --heads origin "$BRANCH" 2>/dev/null | grep -q .; then
  echo "remote_exists: yes"
else
  echo "remote_exists: no"
fi

# Ticket key carried by the branch name, if any. Empty is normal and not an error:
# a branch without a ticket closes exactly the same way, minus the Jira step.
TICKET=$(printf '%s' "$BRANCH" | grep -oE '[A-Z]+-[0-9]+' | head -1 || true)
echo "ticket: ${TICKET:-none}"

# Worktree hosting this branch, if the branch was opened by start-ticket.
WT=$(git worktree list --porcelain 2>/dev/null \
  | awk -v b="refs/heads/$BRANCH" '/^worktree /{p=$2} $0=="branch "b{print p; exit}' || true)
echo "worktree: ${WT:-none}"

if [ "$UNMERGED_N" -gt 0 ]; then
  echo "--- commits NOT in $BASE (would be lost on delete unless in a merged PR/main) ---"
  printf '%s\n' "$UNMERGED"
fi
if [ "$STASH_N" -gt 0 ]; then
  echo "--- stash entries (verify none belong to this branch) ---"
  printf '%s\n' "$STASH"
fi
exit 0
