#!/usr/bin/env bash
# Preview the clipboard as markdown in a popup, confirm, then open it in nvim
# with MarkdownPreview. Invoked from `prefix p` via display-popup -E.
#
# $1 — name of the window this was launched from (for the new window's label)
# $2 — directory to open the new window in
set -euo pipefail

src_window=${1:-?}
src_dir=${2:-$HOME}
tmp=/tmp/claude-preview.md

pbpaste >"$tmp"

if [[ ! -s "$tmp" ]]; then
    printf '\nClipboard is empty — nothing to preview.\n'
    read -rsn1 -p 'Press any key to close…'
    exit 0
fi

# Scrollable markdown preview (q to quit the pager).
bat --style=plain --language=markdown --paging=always "$tmp"

printf '\nOpen in nvim MarkdownPreview? [y/N] '
read -r ans
case "$ans" in
    [yY]*)
        tmux new-window -c "$src_dir" -n "md:${src_window}" \
            "nvim '+MarkdownPreview' '$tmp'"
        ;;
    *)
        : # cancelled — popup just closes
        ;;
esac
