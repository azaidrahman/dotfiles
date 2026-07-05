#!/usr/bin/env bash
# Helper for dir-picker-hunk.sh: list one directory level. First line is the
# directory itself (consumed by fzf as a pinned header via --header-lines=1);
# remaining lines are its git worktrees if it has any, else its immediate
# subdirectories.
set -euo pipefail

dir=${1:?directory required}

printf '%s\n' "$dir"

wt=$(git -C "$dir" worktree list --porcelain 2>/dev/null | awk -v skip="$dir" '/^worktree /{ if ($2 != skip) print $2 }')
if [[ -n "$wt" ]]; then
  printf '%s\n' "$wt"
else
  find "$dir" -mindepth 1 -maxdepth 1 -type d \( -name .git -o -name node_modules \) -prune -o -type d -print 2>/dev/null
fi
