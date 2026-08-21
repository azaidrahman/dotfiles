#!/usr/bin/env bash
# Remove branch-pane worktrees that are safe to drop: clean working tree AND
# no commits unique to the branch. Dirty / unmerged forks are left alone.
#
# Usage:
#   branch-pane-clean.sh            # sweep every .worktrees/* fork
#   branch-pane-clean.sh main-2097  # clean one specific worktree by name
set -euo pipefail

REPO=$(git rev-parse --show-toplevel)
TARGET="${1:-}"

# Build the list of candidate worktrees (paths under .worktrees/, skip the main one)
mapfile -t WTS < <(git worktree list --porcelain \
  | awk '/^worktree /{print $2}' \
  | grep "/.worktrees/" || true)

if [ "${#WTS[@]}" -eq 0 ]; then
  echo "branch-pane-clean: no .worktrees/* forks found."
  exit 0
fi

removed=0 kept=0
for WT in "${WTS[@]}"; do
  NAME=$(basename "$WT")
  [ -n "$TARGET" ] && [ "$NAME" != "$TARGET" ] && continue

  BR=$(git -C "$WT" rev-parse --abbrev-ref HEAD)

  # Dirty? leave it.
  if [ -n "$(git -C "$WT" status --porcelain)" ]; then
    echo "keep   $NAME — uncommitted changes"; kept=$((kept+1)); continue
  fi

  # Commits unique to this branch (not on any other local branch)? leave it.
  OTHERS=$(git for-each-ref --format='%(refname)' refs/heads/ | grep -v "refs/heads/${BR}$")
  UNIQUE=$(git -C "$WT" rev-list --count "$BR" --not $OTHERS 2>/dev/null || echo 0)
  if [ "${UNIQUE:-0}" -ne 0 ]; then
    echo "keep   $NAME — $UNIQUE unmerged commit(s) on $BR"; kept=$((kept+1)); continue
  fi

  git worktree remove "$WT"
  git branch -D "$BR" >/dev/null 2>&1 || true
  echo "remove $NAME ($BR)"; removed=$((removed+1))
done

echo "done — removed $removed, kept $kept."
