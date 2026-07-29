#!/usr/bin/env bash
# prefix+e launcher: review a git worktree's working-tree changes with `tuicr`.
# Invoked via run-shell so tmux expands the #{...} formats into the args below.
#
# This is a gate, and it owns every message the user sees:
#
#   not a git work tree          -> tmux status message, no popup
#   more than one worktree       -> popup: worktree-picker.sh (dirty or clean)
#   single worktree, dirty       -> popup: tuicr -w on the pane's cwd
#   single worktree, clean       -> tmux status message, no popup
#
# The picker appears whenever the repo has linked worktrees, because that is
# exactly when "where are the changes I want to review?" is ambiguous. It used to
# appear only when the cwd was CLEAN, which meant a base worktree with your own
# edits could never reach it — the case the picker was built for. See
# docs/superpowers/specs/2026-07-30-prefix-e-worktree-picker-design.md.
#
# Never route to tuicr with nothing to review: tuicr exits 1 on "No changes to
# review" / "Not a repository", display-popup -E closes the moment its command
# exits, so the message would flash and tmux would report `... returned 1`.
# The status-message branches exist to keep that from happening.
#
# `-w/--working-tree` skips tuicr's commit selector and reviews uncommitted
# changes directly. tuicr persists comments to its session store, so they survive
# quitting and Claude can read them back with `tuicr review comments`.
#
# $1 — pane current path (where the git checks run).
# $2 — pane id (passed through for the picker's conditional `cd`).
set -euo pipefail

cwd=${1:?pane path required}
pane_id=${2:?pane id required}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/git-popup-size.sh"

if ! git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tmux display-message "prefix+e: not a git repo"
  exit 0
fi

# `grep -c` exits 1 on a zero count, which set -o pipefail would turn into an
# abort — hence `|| true`. Counting via porcelain works from inside any of the
# repo's worktrees, not just the main one.
worktrees=$(git -C "$cwd" worktree list --porcelain | grep -c '^worktree ' || true)

# No tty is attached under plain run-shell, so anything interactive needs
# display-popup to get one.
if [[ "${worktrees:-0}" -gt 1 ]]; then
  # display-popup -E blocks and PROPAGATES the inner command's exit status, so
  # under set -e a non-zero exit here (picker cancel, tuicr crash inside it)
  # would abort this script before reaching `exit 0` and tmux's run-shell would
  # print a `returned 1` banner. This gate must never hand run-shell a non-zero
  # status, so every popup call is unconditionally `|| true`.
  tmux display-popup -E -w "$POPUP_W" -h "$POPUP_H" -d "$cwd" -T ' worktree → tuicr ' \
    -- ~/.tmux/scripts/worktree-picker.sh "$pane_id" || true
  exit 0
fi

if [[ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]]; then
  # Same reasoning as above: the tree can go clean between the status check
  # just above and the popup opening (an agent commits in that window), or
  # tuicr can exit non-zero on a config/crash — either way this gate must
  # still hand run-shell a zero status.
  tmux display-popup -E -w "$POPUP_W" -h "$POPUP_H" -d "$cwd" -T ' tuicr ' \
    -- tuicr -w || true
  exit 0
fi

tmux display-message "prefix+e: no changes in $(basename "$cwd")"
