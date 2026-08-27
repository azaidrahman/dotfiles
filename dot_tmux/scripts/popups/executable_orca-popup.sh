#!/usr/bin/env bash
# Opens a display-popup with the Orca board (prefix+H), sized from
# orca-popup-size.sh. The popup starts in the repository of the current pane.
#
# Inside the popup:
#   - If the repository has no .orca/, offer to run orca init.
#   - Run orca status.
#   - When the board exits, ask before the popup closes. "n" reopens the board.
#
# $1 — pane current path (where the popup starts)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/orca-popup-size.sh"

cwd=${1:?pane path required}

if [ "${ORCA_POPUP_INNER:-}" != "1" ]; then
  if ! command -v orca >/dev/null 2>&1; then
    tmux display-message "orca is not on PATH (go build -o ~/.local/bin/orca ./cmd/orca)"
    exit 0
  fi
  exec tmux display-popup -E -w "$POPUP_W" -h "$POPUP_H" -d "$cwd" -T " Orca " \
    -- env ORCA_POPUP_INNER=1 "$script_dir/orca-popup.sh" "$cwd"
fi

# ---- inside the popup from here ----
cd "$cwd"

ask() { # ask PROMPT -> 0 for yes
  local a
  read -r -n1 -p "$1 [y/N] " a; echo
  [[ "$a" == [yY] ]]
}

root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$root" ]; then
  echo "Not inside a git repository: $cwd"
  read -r -n1 -p "Press any key to close." _; exit 0
fi
cd "$root"

if [ ! -d .orca ]; then
  echo "No .orca/ in $root"
  if ask "Run orca init here?"; then
    orca init || { read -r -n1 -p "orca init failed. Press any key to close." _; exit 0; }
    echo
  else
    exit 0
  fi
fi

while :; do
  orca status || true
  ask "Close the Orca popup?" && break
done
