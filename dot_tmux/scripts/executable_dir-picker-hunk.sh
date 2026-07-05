#!/usr/bin/env bash
# claude-diff-review.sh's fallback when the triggering pane's cwd has no diff to
# show: fzf the repo's other worktrees (e.g. under .worktrees/), cd the
# triggering pane into the picked one, then try `hunk diff` there in this same
# popup — so picking a dirty worktree drops you straight into its diff instead
# of a second no-op popup. Falls back to a subdirectory walk when cwd isn't
# inside a git repo (no worktrees to list).
#
# Run via `tmux display-popup -d <cwd> -- dir-picker-hunk.sh <pane_id>` — the
# popup's cwd is already <cwd>.
#
# $1 — pane id (where to `cd` once a directory is picked).
set -euo pipefail

pane_id=${1:?pane id required}

candidates=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
if [[ -z "$candidates" ]]; then
  candidates=$(find . -mindepth 1 -maxdepth 4 \( -name .git -o -name node_modules \) -prune -o -type d -print 2>/dev/null)
fi

sel=$(printf '%s\n' "$candidates" \
  | fzf --tac --prompt="cd> " --preview "ls -la --color=always {}") || true

[[ -z "$sel" ]] && exit 0

sel=$(cd "$sel" && pwd)
tmux send-keys -t "$pane_id" "cd -- '$sel'" C-m

if git -C "$sel" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -n $(git -C "$sel" status --porcelain 2>/dev/null) ]]; then
  cd "$sel"
  exec hunk diff
fi

printf '\nno changes in %s\n' "$sel"
read -rsn1 -p "Press any key to close…"
