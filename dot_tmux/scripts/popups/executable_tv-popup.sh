#!/usr/bin/env bash
# Shared launcher for the television popups (prefix+f/F/a), sized from
# tv-popup-size.sh so all three stay in sync from one place.
#
# $1 — popup title
# $2 — pane current path (where the popup starts)
# $3.. — command to run in the popup
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/tv-popup-size.sh"

title=${1:?title required}
cwd=${2:-$HOME}
shift 2

tmux display-popup -E -w "$POPUP_W" -h "$POPUP_H" -d "$cwd" -T " $title " -- bash -c "$*"
