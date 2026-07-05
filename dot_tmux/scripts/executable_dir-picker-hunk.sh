#!/usr/bin/env bash
# claude-diff-review.sh's fallback when the triggering pane's cwd has no diff to
# show: fzf a directory under that cwd (e.g. a sibling worktree under
# .worktrees/), cd the triggering pane there, then try `hunk diff` at the picked
# directory in this same popup — so picking a dirty worktree drops you straight
# into its diff instead of a second no-op popup.
#
# Run via `tmux display-popup -d <cwd> -- dir-picker-hunk.sh <pane_id>` — the
# popup's cwd is already <cwd>, so `find .` walks from there.
#
# $1 — pane id (where to `cd` once a directory is picked).
set -euo pipefail

pane_id=${1:?pane id required}

sel=$(find . -mindepth 1 -maxdepth 4 \( -name .git -o -name node_modules \) -prune -o -type d -print 2>/dev/null \
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
