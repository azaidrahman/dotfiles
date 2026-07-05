#!/usr/bin/env bash
# claude-diff-review.sh's fallback when the triggering pane's cwd has no diff to
# show: an oil.nvim-style directory browser, rooted at that cwd. Each row is a
# directory — the repo's worktrees if the current level has any, else its
# immediate subdirectories (see dir-picker-list.sh). Enter drills into the
# highlighted row, "-" goes up to the parent and re-lists from there. "."
# accepts the highlighted row (falling back to the directory being browsed if
# the listing is empty — see dir-picker-accept.sh): cd's the triggering pane
# there, and opens `hunk diff` right there in this same popup only if that
# directory actually has changes (a clean dir just shows a notice). "h" is the
# explicit override — same target, but opens hunk diff regardless of whether
# there are changes.
#
# Run via `tmux display-popup -d <cwd> -- dir-picker-hunk.sh <pane_id>` — the
# popup's cwd is already <cwd>, which is where browsing starts.
#
# $1 — pane id (where to `cd` once a directory is accepted).
set -euo pipefail

pane_id=${1:?pane id required}
list_script=~/.tmux/scripts/dir-picker-list.sh
accept_script=~/.tmux/scripts/dir-picker-accept.sh

statefile=$(mktemp)
resultfile=$(mktemp)
forcefile=$(mktemp)
trap 'rm -f "$statefile" "$resultfile" "$forcefile"' EXIT

pwd >"$statefile"

"$list_script" "$(cat "$statefile")" | fzf --tac --header-lines=1 --prompt 'cd> ' \
  --preview 'ls -la --color=always {}' \
  --bind "enter:execute-silent(echo {} > '$statefile')+reload($list_script \$(cat '$statefile'))" \
  --bind "-:execute-silent(dirname \"\$(cat '$statefile')\" > '$statefile')+reload($list_script \$(cat '$statefile'))" \
  --bind ".:execute-silent($accept_script {} '$statefile' '$resultfile')+abort" \
  --bind "h:execute-silent($accept_script {} '$statefile' '$forcefile')+abort" \
  >/dev/null || true

if [[ -s "$forcefile" ]]; then
  sel=$(<"$forcefile")
  tmux send-keys -t "$pane_id" "cd -- '$sel'" C-m
  cd "$sel"
  exec hunk diff
fi

[[ -s "$resultfile" ]] || exit 0
sel=$(<"$resultfile")

tmux send-keys -t "$pane_id" "cd -- '$sel'" C-m

if git -C "$sel" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -n $(git -C "$sel" status --porcelain 2>/dev/null) ]]; then
  cd "$sel"
  exec hunk diff
fi

printf '\nno changes in %s\n' "$sel"
read -rsn1 -p "Press any key to close…"
