#!/usr/bin/env bash
# prefix+e's directory browser: an oil.nvim-style picker, rooted at the
# triggering pane's cwd, for jumping to a worktree (or any directory) and
# reviewing its changes. Each row is a directory — the repo's worktrees if the
# current level has any, else its immediate subdirectories (see
# dir-picker-list.sh). The current level's own path is pinned as the header.
#
# Keys:
#   Enter   go to the highlighted directory: cd the triggering pane there (only
#           if a real shell owns it — see below) and open `hunk diff` on it
#           right here in this same popup (shows changes, or an empty diff if
#           the dir is clean — it's the "take me there and show me" action).
#   → / Tab browse INTO the highlighted directory (re-list from there, one level
#           deeper) without leaving the picker.
#   ← / -   go UP to the parent directory and re-list from there.
#
# Enter always opens hunk regardless of clean/dirty state — if you explicitly
# picked a directory you want to see it, even to confirm it's clean. The `cd`
# is skipped if the triggering pane isn't running a shell (e.g. Claude Code is
# running there instead) — typing "cd ..." into a non-shell program would just
# paste literal text into it.
#
# Run via `tmux display-popup -d <cwd> -- dir-picker-hunk.sh <pane_id>` — the
# popup's cwd is already <cwd>, which is where browsing starts.
#
# $1 — pane id (where to `cd` once a directory is chosen).
set -euo pipefail

pane_id=${1:?pane id required}
list_script=~/.tmux/scripts/dir-picker-list.sh
accept_script=~/.tmux/scripts/dir-picker-accept.sh

statefile=$(mktemp)
resultfile=$(mktemp)
trap 'rm -f "$statefile" "$resultfile"' EXIT

pwd >"$statefile"

# reload target = highlighted row {} (drill in) or parent (go up). Both persist
# the new level to $statefile so a subsequent reload/accept knows where it is.
drill="execute-silent(echo {} > '$statefile')+reload($list_script \$(cat '$statefile'))"
up="execute-silent(dirname \"\$(cat '$statefile')\" > '$statefile')+reload($list_script \$(cat '$statefile'))"

"$list_script" "$(cat "$statefile")" | fzf --tac --header-lines=1 --prompt 'go> ' \
  --preview 'ls -la --color=always {}' \
  --bind "enter:execute-silent($accept_script {} '$statefile' '$resultfile')+abort" \
  --bind "right:$drill" \
  --bind "tab:$drill" \
  --bind "left:$up" \
  --bind "-:$up" \
  >/dev/null || true

[[ -s "$resultfile" ]] || exit 0
sel=$(<"$resultfile")

# Only type `cd` into the triggering pane if a real shell owns it — e.g. when
# Claude Code (or any other TUI) is running there instead, sending keystrokes
# just pastes literal text into its input box rather than executing anything.
case "$(tmux display-message -p -t "$pane_id" '#{pane_current_command}')" in
  sh | bash | zsh | fish) tmux send-keys -t "$pane_id" "cd -- '$sel'" C-m ;;
esac

cd "$sel"
exec hunk diff
