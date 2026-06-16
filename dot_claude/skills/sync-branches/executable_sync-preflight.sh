#!/usr/bin/env bash
# sync-preflight.sh — read-only feasibility report for sync-branches.
#
# For each target in the chain, says whether a fast-forward-only merge is possible and how
# many commits would move. Fetches refs (safe, non-destructive) but performs NO merge, push,
# or checkout. The actual ff-only merge/push loop and the main-branch confirmation stay in
# the skill — this just makes the go/no-go deterministic.
#
# Usage:  sync-preflight.sh [TARGET...]      # default chain: develop  (e.g. `develop main`)
# stdout: per-target report
# Exit:   0  at least one target is ff-able — proceed to the skill's merge step
#         5  no target is ff-able (branches diverged — rebase needed)
#         2  precondition failure (not a repo / detached / on base / dirty)
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "stop: not inside a git repo"; exit 2; }
FEAT=$(git branch --show-current)
[ -n "$FEAT" ] || { echo "stop: detached HEAD"; exit 2; }
case "$FEAT" in main|master|develop) echo "stop: on base branch ($FEAT) — switch to a feature branch"; exit 2 ;; esac
[ -z "$(git status --porcelain)" ] || { echo "stop: working tree dirty — commit or stash first"; exit 2; }

# Default chain is just develop.
if [ "$#" -eq 0 ]; then set -- develop; fi

git fetch --prune origin >/dev/null 2>&1 || true
echo "feature: $FEAT"
echo "chain: $*"

prev="$FEAT"          # source for the first target is the feature branch
any_ff=0
for tgt in "$@"; do
  ref="origin/$tgt"
  if ! git show-ref --verify --quiet "refs/remotes/$ref"; then
    echo "target $tgt: MISSING on origin — skip"
    prev="$tgt"; continue
  fi
  # ff-only from $prev into $tgt is possible iff origin/$tgt is an ancestor of $prev.
  src_ref=$prev
  git show-ref --verify --quiet "refs/remotes/origin/$prev" && src_ref="origin/$prev" || src_ref="$prev"
  ahead=$(git rev-list --count "$ref..$src_ref" 2>/dev/null || echo 0)
  behind=$(git rev-list --count "$src_ref..$ref" 2>/dev/null || echo 0)
  if git merge-base --is-ancestor "$ref" "$src_ref" 2>/dev/null; then
    echo "target $tgt: ff_possible=yes  would_merge=$ahead commit(s) from $prev"
    any_ff=1
  else
    echo "target $tgt: ff_possible=no  (diverged: $ahead ahead / $behind behind $prev) — rebase needed"
  fi
  prev="$tgt"
done

[ "$any_ff" -eq 1 ] && exit 0 || exit 5
