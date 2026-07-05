#!/usr/bin/env bash
# claude-diff-review.sh's fallback when the triggering pane's cwd has no diff to
# show: fzf the repo's other worktrees (e.g. under .worktrees/), cd the
# triggering pane into the picked one, then try `hunk diff` there in this same
# popup — so picking a dirty worktree drops you straight into its diff instead
# of a second no-op popup. Falls back to a subdirectory walk when the current
# level isn't inside a git repo (no worktrees to list). A ".." entry lets you
# walk up and re-list from there, so you're not stuck one level deep.
#
# Run via `tmux display-popup -d <cwd> -- dir-picker-hunk.sh <pane_id>` — the
# popup's cwd is already <cwd>.
#
# $1 — pane id (where to `cd` once a directory is picked).
set -euo pipefail

pane_id=${1:?pane id required}

while true; do
  entries=()
  [[ $PWD != / ]] && entries+=("..")

  wt=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
  if [[ -n "$wt" ]]; then
    while IFS= read -r line; do entries+=("$line"); done <<<"$wt"
  else
    while IFS= read -r line; do entries+=("$line"); done < <(
      find . -mindepth 1 -maxdepth 1 -type d \( -name .git -o -name node_modules \) -prune -o -type d -print 2>/dev/null
    )
  fi

  sel=$(printf '%s\n' "${entries[@]}" \
    | fzf --tac --prompt="${PWD}> " --preview "ls -la --color=always {}") || true

  [[ -z "$sel" ]] && exit 0

  if [[ "$sel" == ".." ]]; then
    cd ..
    continue
  fi

  break
done

sel=$(cd "$sel" && pwd)
tmux send-keys -t "$pane_id" "cd -- '$sel'" C-m

if git -C "$sel" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -n $(git -C "$sel" status --porcelain 2>/dev/null) ]]; then
  cd "$sel"
  exec hunk diff
fi

printf '\nno changes in %s\n' "$sel"
read -rsn1 -p "Press any key to close…"
