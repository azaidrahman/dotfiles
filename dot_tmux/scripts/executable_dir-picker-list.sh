#!/usr/bin/env bash
# Helper for dir-picker-hunk.sh: list one directory level. First line is the
# directory itself (consumed by fzf as a pinned header via --header-lines=1);
# remaining lines are its sibling git worktrees, if $dir is itself a worktree
# root, else its immediate subdirectories.
#
# `git worktree list` succeeds from ANY directory inside a repo's working
# tree, not just a worktree's own root (e.g. from inside .worktrees/, which is
# just a plain subdirectory of the main worktree) — so it's gated on $dir
# being a worktree root itself, otherwise every level below one would show
# the same repo-wide worktree list and going up would look like a no-op.
set -euo pipefail

dir=${1:?directory required}

printf '%s\n' "$dir"

toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -n "$toplevel" && "$dir" == "$toplevel" ]]; then
  git -C "$dir" worktree list --porcelain | awk -v skip="$dir" '/^worktree /{ if ($2 != skip) print $2 }'
else
  find "$dir" -mindepth 1 -maxdepth 1 -type d \( -name .git -o -name node_modules \) -prune -o -type d -print 2>/dev/null
fi
