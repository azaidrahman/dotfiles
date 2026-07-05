#!/usr/bin/env bash
# Helper for dir-picker-hunk.sh's "." and "h" binds: accept the row currently
# highlighted by fzf's cursor ($1), or fall back to the directory being
# browsed ($2) when the listing is empty (a leaf directory with no
# subdirectories has nothing for the cursor to highlight).
set -euo pipefail

highlighted=${1:-}
statefile=${2:?statefile required}
outfile=${3:?outfile required}

if [[ -n "$highlighted" ]]; then
  printf '%s' "$highlighted" >"$outfile"
else
  cp "$statefile" "$outfile"
fi
