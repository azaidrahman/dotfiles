#!/bin/bash
# prefix+? : my custom keybindings (pulled from keys.conf) shown first,
# then the full stock `tmux list-keys` dump underneath. Nothing is lost vs
# the default ? binding — this just prepends a readable summary of MY keys.

CONF="$HOME/.tmux/conf.d/keys.conf"
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
  echo
  echo "== ALL KEYS (tmux list-keys) =="
  echo
  tmux list-keys
} | "${PAGER[@]}"
