#!/usr/bin/env bash
# Shared markdown viewer: preview a file with bat in the current popup, confirm,
# then open it in a new nvim window with MarkdownPreview auto-fired. The single
# home for the open-in-nvim flow, reused by the clipboard preview (prefix+P /
# md-preview.sh) and the pane .md picker (prefix+) / pane-md-preview.sh + md-pick.sh).
#
# Usage: md-open.sh [--no-confirm] <file> [src_window] [src_dir]
#   --no-confirm  skip the bat preview + y/N gate and open in nvim immediately
#                 (used when the caller — e.g. the fzf picker — already previewed).
#
# <file>       — markdown file to preview/open
# [src_window] — source window name (the new window is named md:<name>)
# [src_dir]    — directory to open the new window in
set -euo pipefail

confirm=1
if [[ ${1:-} == --no-confirm ]]; then
    confirm=0
    shift
fi

file=${1:?file required}
src_window=${2:-?}
src_dir=${3:-$HOME}

open_in_nvim() {
    tmux new-window -c "$src_dir" -n "md:${src_window}" \
        "nvim '+MarkdownPreview' '$file'"
}

# Picker path already previewed the file — open straight away.
if (( confirm == 0 )); then
    open_in_nvim
    exit 0
fi

if [[ ! -s "$file" ]]; then
    printf '\nNothing to preview (%s is empty or missing).\n' "$file"
    read -rsn1 -p 'Press any key to close…'
    exit 0
fi

# Scrollable markdown preview (q to quit the pager). bat renders the markdown;
# fall back to less -R if bat isn't installed (matches keys-cheatsheet.sh).
if command -v bat >/dev/null; then
    bat --style=plain --language=markdown --paging=always "$file"
else
    less -R "$file"
fi

printf '\nOpen in nvim MarkdownPreview? [y/N] '
read -r ans
case "$ans" in
    [yY]*) open_in_nvim ;;
    *)     : ;; # cancelled — popup just closes
esac
