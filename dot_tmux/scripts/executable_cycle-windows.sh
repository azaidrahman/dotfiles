#!/usr/bin/env bash
# Cycle prefix+[ / prefix+] through the same filtered window set as the
# `tmux-windows` tv channel (prefix+f), in a stable spatial order.
#   $1 = direction: next | prev
#   $2 = current target as session:window_index (passed by the binding)
set -u
dir="${1:-next}"; cur="${2:-}"

# Same exclusions as tv-tmux-windows.sh; stable order: session, then window idx.
mapfile -t t < <(
  tmux list-windows -a -F '#{session_name}	#{window_index}	#{window_name}' \
    | awk -F'\t' '$1=="mobile"||$1=="quickterminal"{next} $3~/^md:/{next} {print $1":"$2}' \
    | sort -t: -k1,1 -k2,2n
)
n=${#t[@]}; [ "$n" -eq 0 ] && exit 0

i=0; for x in "${t[@]}"; do [ "$x" = "$cur" ] && break; i=$((i+1)); done
[ "$i" -ge "$n" ] && i=0
if [ "$dir" = prev ]; then i=$(((i-1+n)%n)); else i=$(((i+1)%n)); fi

tmux switch-client -t "${t[$i]}"
