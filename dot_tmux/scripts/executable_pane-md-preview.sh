#!/usr/bin/env bash
# prefix+) viewer: scan a pane (visible + scrollback) for every .md file path it
# mentions, then preview one via md-open.sh (the shared bat -> nvim
# MarkdownPreview flow). One existing hit opens straight into the preview;
# multiple hits hand off to md-pick.sh for an fzf picker (with a bat preview
# pane) so you can scroll and choose. Handy for jumping from a path Claude
# printed — plans, specs, READMEs, … — into a rendered view.
#
# Invoked via run-shell so tmux expands the #{...} formats into the args below.
# The (non-interactive) capture + resolve happens here, where tmux access is
# reliable; then we open a popup for the interactive pick/preview, passing plain
# values (display-popup does NOT expand formats in its command). Mirrors the
# claude-diff-review.sh pattern.
#
# $1 — origin pane id (to scan)
# $2 — origin window name (for the new window's md:<name> label)
# $3 — origin pane dir (resolve relative paths against / open the new window in)
set -euo pipefail

pane_id=${1:?pane id required}
src_window=${2:-?}
src_dir=${3:-$HOME}
list=/tmp/md-pane-list.txt

hold() {
    tmux display-popup -E -w 80% -h 80% -d "$src_dir" -T ' Markdown Preview ' \
        -e "MSG=$1" 'printf "\n%s\n" "$MSG"; read -rsn1 -p "Press any key to close…"'
}

# Every .md-looking path in the pane, bottom (newest) first.
mapfile -t hits < <(tmux capture-pane -p -t "$pane_id" -S -3000 \
    | grep -oE '[[:alnum:]~./_-]+\.md' | tail -r 2>/dev/null || true)

# Roots to resolve relative paths against: the pane's cwd, plus any linked git
# worktrees. A pane's cwd is often the main repo while the path printed (e.g. by
# Claude) is relative to a worktree — so cwd+path alone misses it. Try each root.
roots=("$src_dir")
if git -C "$src_dir" rev-parse --git-dir >/dev/null 2>&1; then
    while IFS= read -r line; do
        [[ $line == "worktree "* ]] && roots+=("${line#worktree }")
    done < <(git -C "$src_dir" worktree list --porcelain 2>/dev/null || true)
fi

# Resolve each, keep the ones that exist, dedupe (most-recent mention wins).
declare -A seen
candidates=()
for raw in "${hits[@]}"; do
    f=""
    case "$raw" in
        "~/"*) [[ -f "${raw/#\~/$HOME}" ]] && f="${raw/#\~/$HOME}" ;;
        /*)    [[ -f "$raw" ]] && f="$raw" ;;
        *)     for root in "${roots[@]}"; do
                   [[ -f "$root/$raw" ]] && { f="$root/$raw"; break; }
               done ;;
    esac
    [[ -n $f ]] || continue
    [[ -n ${seen[$f]:-} ]] && continue
    seen[$f]=1
    candidates+=("$f")
done

if (( ${#candidates[@]} == 0 )); then
    hold 'No .md file path found in this pane.' || true
    exit 0
fi

printf '%s\n' "${candidates[@]}" > "$list"

tmux display-popup -EE -w 80% -h 80% -d "$src_dir" -T ' Markdown Preview ' \
    "$HOME/.tmux/scripts/md-pick.sh '$list' '$src_window' '$src_dir'"
