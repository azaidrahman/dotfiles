#!/usr/bin/env bash
# Popup-side chooser for the pane .md preview (prefix+)). Given a newline list of
# existing .md files (newest first), open one via md-open.sh. A single entry
# goes straight to md-open's preview + confirm; multiple entries get an fzf
# picker with a bat preview pane (falls back to a numbered menu without fzf).
#
# $1 — path to the newline-delimited list of files
# $2 — source window name (md:<name> label, forwarded to md-open)
# $3 — directory to open the new window in (forwarded to md-open)
set -euo pipefail

list=${1:?list file required}
src_window=${2:-?}
src_dir=${3:-$HOME}

mapfile -t files < "$list"
(( ${#files[@]} == 0 )) && exit 0

launch() { exec "$HOME/.tmux/scripts/md-open.sh" "$@" "$src_window" "$src_dir"; }

# Single hit: hand straight to md-open (preview + confirm).
(( ${#files[@]} == 1 )) && launch "${files[0]}"

if command -v fzf >/dev/null; then
    sel=$(printf '%s\n' "${files[@]}" | fzf --reverse --prompt='open md > ' \
        --preview='bat --color=always --style=plain {} 2>/dev/null || cat {}' \
        --preview-window='right:60%') || exit 0
    [[ -z $sel ]] && exit 0
    launch --no-confirm "$sel"   # fzf already previewed -> open straight away
else
    PS3=$'\nPick a file (number, Ctrl-C to cancel): '
    select sel in "${files[@]}"; do
        [[ -n ${sel:-} ]] && break
    done
    [[ -z ${sel:-} ]] && exit 0
    launch "$sel"                # no fzf preview -> let md-open preview + confirm
fi
