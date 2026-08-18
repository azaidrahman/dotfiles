#!/bin/bash
# prefix+? : my custom keybindings (pulled from keys.conf) and my custom
# commands (pulled from ~/.local/bin) shown first, then the full stock
# `tmux list-keys` dump underneath. Nothing is lost vs the default ? binding —
# this just prepends a readable summary of MY keys and MY commands.

CONF="$HOME/.tmux/conf.d/keys.conf"
BIN="$HOME/.local/bin"
PREFIX=$(tmux show -gv prefix 2>/dev/null | sed 's/^C-/Ctrl+/')

if command -v bat >/dev/null; then
  PAGER=(bat --style=plain --paging=always)
else
  PAGER=(less -R)
fi

{
  echo "== MY KEYS ($PREFIX + …) =="
  echo
  awk -v prefix="$PREFIX" '
  function fmtkey(line,   n, arr, i, tok, key, repeat) {
    sub(/^bind(-key)?[ \t]+/, "", line)
    n = split(line, arr, /[ \t]+/); repeat=""; i=1
    while (i <= n) {
      tok = arr[i]
      if (tok == "-r") { repeat = " (hold)"; i++; continue }
      if (tok == "-T") { i += 2; continue }
      break
    }
    key = arr[i]; gsub(/"/, "", key); return key repeat
  }
  /^#/   { sub(/^#+[ \t]*/, ""); desc = $0; next }
  /^$/   { desc = ""; next }
  /^unbind/ { next }
  /^bind/ {
    if ($0 ~ /-n[ \t]/ || $0 ~ /-T[ \t]+copy-mode/) { desc = ""; next }
    printf "  %-8s  %s\n", fmtkey($0), desc; desc = ""
  }
  ' "$CONF"
  echo
  echo "== NO-PREFIX KEYS (work without $PREFIX) =="
  echo
  awk '
  function fmtkey(line,   n, arr, i, tok, key, repeat) {
    sub(/^bind(-key)?[ \t]+/, "", line)
    n = split(line, arr, /[ \t]+/); repeat=""; i=1
    while (i <= n) {
      tok = arr[i]
      if (tok == "-r") { repeat = " (hold)"; i++; continue }
      if (tok == "-n") { i++; continue }
      break
    }
    key = arr[i]; gsub(/"/, "", key); return key repeat
  }
  /^#/   { sub(/^#+[ \t]*/, ""); desc = $0; next }
  /^$/   { desc = ""; next }
  /^unbind/ { next }
  /^bind/ {
    if ($0 !~ /-n[ \t]/) { desc = ""; next }
    printf "  %-8s  %s\n", fmtkey($0), desc; desc = ""
  }
  ' "$CONF"

  # Root-table keys that tmux has but keys.conf never declares: they come from
  # plugins (vim-tmux-navigator owns C-h/j/k/l and C-\\). Without this they are
  # invisible here, and you rediscover them by binding over them.
  mine=$(grep -oE '^bind(-key)?[ \t]+-n[ \t]+[^ \t]+' "$CONF" | awk '{print $NF}' | tr -d '"')
  # Mouse/wheel events are not keys you can type — drop them, the stock
  # list-keys dump below still has them.
  tmux list-keys -T root 2>/dev/null | awk '{print $4}' |
    grep -vE 'Mouse|Click|Wheel|Drag' | sort -u |
    while read -r k; do
      [ -n "$k" ] || continue
      printf '%s\n' "$mine" | grep -qxF "$k" && continue
      # list-keys escapes the backslash key as C-\\; show it as typed.
      printf "  %-8s  %s\n" "${k//\\\\/\\}" "(from a plugin)"
    done

  echo
  echo "== NO-PREFIX GOTCHAS =="
  echo
  echo "  Ctrl+option only reaches tmux with the LEFT option key. Left ctrl +"
  echo "  RIGHT option is Karabiner Shortcut Layer 2 (see karabiner.edn), which"
  echo "  swallows every letter, digit, and symbol before the terminal sees it."
  echo
  echo "  Ctrl+[ can never be bound: it is byte 0x1B, the same byte as Escape."
  echo "  tmux cannot tell them apart. Ctrl+] (0x1D) is free and safe to bind."
  echo
  echo "  Ctrl+option+l is taken by the Todoist global quick add."
  echo
  echo "== MY COMMANDS (~/.local/bin) =="
  echo
  # One entry per script that documents itself with a "# <name> - <summary>"
  # line in its first 10 lines. A script without that line is plumbing that I
  # never call by hand (credential helpers, agent seeding), so leaving it out
  # is the point: add the header line and it appears here.
  for f in "$BIN"/*; do
    [ -f "$f" ] && [ -x "$f" ] || continue
    name=${f##*/}
    # LC_ALL=C: ~/.local/bin also holds symlinks to binaries (ssh-keygen), and
    # sed aborts with "illegal byte sequence" on those under a UTF-8 locale.
    summary=$(head -10 "$f" 2>/dev/null | LC_ALL=C sed -n "s/^# *${name} *- *//p" | head -1)
    [ -n "$summary" ] || continue
    # git-* scripts are git subcommands; show how you actually type them.
    case "$name" in
      git-*) name="git ${name#git-}" ;;
    esac
    printf "  %-20s  %s\n" "$name" "$summary"
  done

  echo
  echo "== ALL KEYS (tmux list-keys) =="
  echo
  tmux list-keys
} | "${PAGER[@]}"
