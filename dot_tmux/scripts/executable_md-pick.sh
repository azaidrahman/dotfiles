#!/usr/bin/env bash
# Popup-side chooser for the pane .md preview (prefix+)). Given a newline list of
# existing .md files (newest first), pick one in a two-pane fzf selector — the
# list on the left, a bat render on the right — then open it via md-open.sh.
# The preview pane carries the name of the file only, not the full path.
# Enter opens the file. q asks first if you want to leave. Escape leaves at once.
# Without fzf, the script falls back to a numbered menu.
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

if command -v fzf >/dev/null; then
    # q gates the exit: the confirm runs in `execute` (which gives it the whole
    # terminal), and drops a flag file if you agree. The chained `transform`
    # reads that flag and turns it into the abort action.
    quit_flag=$(mktemp -t md-pick-quit)
    rm -f "$quit_flag"
    trap 'rm -f "$quit_flag"' EXIT

    # Feed "<label>TAB<full path>"; show field 1, preview and return field 2.
    sel=$(for f in "${files[@]}"; do printf '%s\t%s\n' "$(short "$f")" "$f"; done \
        | fzf --reverse --prompt='open md > ' --delimiter='\t' --with-nth=1 \
        --preview='bat --color=always --style=plain {2} 2>/dev/null || cat {2}' \
        --preview-window='right:60%,border-rounded' \
        --bind='focus:transform-preview-label:printf " %s " "$(basename {2})"' \
        --bind="q:execute(printf '\nLeave the markdown picker? [y/N] '; read -r a; [[ \$a == [yY]* ]] && touch '$quit_flag')+transform([[ -f '$quit_flag' ]] && echo abort || echo ignore)") || exit 0
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
