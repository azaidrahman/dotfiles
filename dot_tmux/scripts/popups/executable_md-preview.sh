#!/usr/bin/env bash
# prefix+P viewer: dump the clipboard to a temp file and preview it via
# md-open.sh (the shared bat-preview -> nvim MarkdownPreview flow). The clipboard
# is the hand-off, so this works with Claude's /copy or any copy-mode `y` yank.
#
# Invoked via run-shell so tmux expands the #{...} formats into the args below;
# the clipboard grab happens here, then we open a popup for the interactive
# preview, passing plain values (display-popup does NOT expand formats in its
# command). Mirrors the claude-diff-review.sh pattern.
#
# $1 — origin window name (for the new window's md:<name> label)
# $2 — directory to open the new window in
set -euo pipefail

src_window=${1:-?}
src_dir=${2:-$HOME}
tmp=/tmp/claude-preview.md

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/md-popup-size.sh"

pbpaste >"$tmp"

tmux display-popup -E -w "$POPUP_W" -h "$POPUP_H" -d "$src_dir" -T ' Markdown Preview ' \
    "$HOME/.tmux/scripts/md-open.sh '$tmp' '$src_window' '$src_dir'"
