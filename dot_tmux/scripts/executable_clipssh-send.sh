#!/usr/bin/env bash
#
# prefix+i helper: send the clipboard screenshot to the other machine with
# clipssh, then report the remote path in the tmux status line. clipssh puts
# that path on the local clipboard, so the next paste is the path itself.
#
# The target host comes from, in order:
#   1. $CLIPSSH_HOST, if set in the tmux session environment
#   2. the other machine (on onyx -> aqua, on aqua -> onyx)
#
# tmux run-shell does not give this script the login PATH, so add the two
# directories that hold clipssh and pngpaste.
#
set -uo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

host="${CLIPSSH_HOST:-}"
if [ -z "$host" ]; then
  case "$(hostname -s | tr '[:upper:]' '[:lower:]')" in
    onyx*) host="aqua" ;;
    aqua*) host="onyx" ;;
    *) tmux display-message "clipssh: unknown host, set CLIPSSH_HOST"; exit 1 ;;
  esac
fi

out=$(clipssh "$host" 2>&1)
status=$?

if [ "$status" -ne 0 ]; then
  # Show only the last line; clipssh errors are one line and colorized.
  tmux display-message "clipssh -> $host failed: $(printf '%s' "$out" | tail -n1 | tr -d '\033' | sed 's/\[[0-9;]*m//g')"
  exit "$status"
fi

path=$(printf '%s' "$out" | sed -n 's/^.*Uploaded: //p' | tail -n1 | tr -d '\033' | sed 's/\[[0-9;]*m//g')
tmux display-message "clipssh -> $host: ${path:-uploaded} (path on clipboard)"
