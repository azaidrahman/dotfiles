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

# Short label for a path — the popup is narrow, so absolute paths waste the row.
# If the path goes through a projects/ directory, start the label there.
# If not, replace the home directory with ~.
short() {
    local p=$1
    case "$p" in
        */projects/*) printf 'projects/%s\n' "${p#*/projects/}" ;;
        "$HOME"/*)    printf '~/%s\n' "${p#"$HOME"/}" ;;
        *)            printf '%s\n' "$p" ;;
    esac
}

# Single hit: hand straight to md-open (preview + confirm).
(( ${#files[@]} == 1 )) && launch "${files[0]}"

if command -v fzf >/dev/null; then
    # Feed "<label>TAB<full path>"; show field 1, preview and return field 2.
    sel=$(for f in "${files[@]}"; do printf '%s\t%s\n' "$(short "$f")" "$f"; done \
        | fzf --reverse --prompt='open md > ' --delimiter='\t' --with-nth=1 \
        --preview='printf "\033[1;36m%s\033[0m\n\n" "$(basename {2})"; bat --color=always --style=plain {2} 2>/dev/null || cat {2}' \
        --preview-window='right:60%') || exit 0
    [[ -z $sel ]] && exit 0
    launch --no-confirm "${sel#*$'\t'}"   # fzf already previewed -> open straight away
else
    labels=()
    for f in "${files[@]}"; do labels+=("$(short "$f")"); done
    PS3=$'\nPick a file (number, Ctrl-C to cancel): '
    select sel in "${labels[@]}"; do
        [[ -n ${sel:-} ]] && break
    done
    [[ -z ${sel:-} ]] && exit 0
    launch "${files[$((REPLY - 1))]}"     # no fzf preview -> let md-open preview + confirm
fi
