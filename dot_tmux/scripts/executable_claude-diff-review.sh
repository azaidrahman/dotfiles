#!/usr/bin/env bash
# prefix+e launcher: open `hunk diff` in a popup to review the working-tree
# changes of the active pane's repo. Invoked via run-shell so tmux expands the
# #{...} format into the arg below.
#
# hunk auto-reloads as the working tree changes, so the popup stays live while
# an agent keeps editing in another pane. Claude drives the same live session
# via `hunk session ...` (see the bundled hunk-review skill).
#
# Clean repo, or not a repo: shows a popup notification instead of opening an
# empty hunk session.
#
# $1 — pane current path (where to look for changes / open hunk).
set -euo pipefail

cwd=${1:?pane path required}

# True when $1 is inside a git work tree that has changes (tracked or untracked).
has_changes() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [[ -n $(git -C "$1" status --porcelain 2>/dev/null) ]]
}

open_hunk() {
  tmux display-popup -E -w 96% -h 96% -d "$1" -- hunk diff
}

# No tty is attached under plain run-shell, so an fzf/select picker here would
# hang silently — display-popup is what actually gets a tty (see hold() in
# pane-md-preview.sh), so a real notification goes through it too.
notify_no_changes() {
  tmux display-popup -E -w 40% -h 20% -T ' diff-review ' \
    -e "MSG=no changes in $1" 'printf "\n%s\n" "$MSG"; read -rsn1 -p "Press any key to close…"'
}

if has_changes "$cwd"; then
  open_hunk "$cwd"
else
  notify_no_changes "$cwd"
fi
