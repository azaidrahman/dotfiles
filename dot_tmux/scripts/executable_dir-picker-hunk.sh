#!/usr/bin/env bash
# claude-diff-review.sh's fallback when the triggering pane's cwd has no diff to
# show: an oil.nvim-style directory browser, rooted at that cwd. Each row is a
# directory — the repo's worktrees if the current level has any, else its
# immediate subdirectories (see dir-picker-list.sh). Enter drills into the
# highlighted row, "-" goes up to the parent and re-lists from there, "."
# accepts wherever you're currently sitting. Once accepted, the triggering
# pane is cd'd there and, if that directory has changes, `hunk diff` runs
# right there in this same popup.
#
# Run via `tmux display-popup -d <cwd> -- dir-picker-hunk.sh <pane_id>` — the
# popup's cwd is already <cwd>, which is where browsing starts.
#
# $1 — pane id (where to `cd` once a directory is accepted).
set -euo pipefail

pane_id=${1:?pane id required}
list_script=~/.tmux/scripts/dir-picker-list.sh

statefile=$(mktemp)
resultfile=$(mktemp)
trap 'rm -f "$statefile" "$resultfile"' EXIT

pwd >"$statefile"

"$list_script" "$(cat "$statefile")" | fzf --tac --header-lines=1 --prompt 'cd> ' \
  --preview 'ls -la --color=always {}' \
  --bind "enter:execute-silent(echo {} > '$statefile')+reload($list_script \$(cat '$statefile'))" \
  --bind "-:execute-silent(dirname \"\$(cat '$statefile')\" > '$statefile')+reload($list_script \$(cat '$statefile'))" \
  --bind ".:execute-silent(cat '$statefile' > '$resultfile')+abort" \
  >/dev/null || true

[[ -s "$resultfile" ]] || exit 0
sel=$(<"$resultfile")

tmux send-keys -t "$pane_id" "cd -- '$sel'" C-m

if git -C "$sel" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -n $(git -C "$sel" status --porcelain 2>/dev/null) ]]; then
  cd "$sel"
  exec hunk diff
fi

printf '\nno changes in %s\n' "$sel"
read -rsn1 -p "Press any key to close…"
