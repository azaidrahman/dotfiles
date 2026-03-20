#!/usr/bin/env bash

# Custom path widget with max length truncation (update-safe)

# get value from tmux config
SHOW_PATH=$(tmux show-option -gv @tokyo-night-tmux_show_path 2>/dev/null)
PATH_FORMAT=$(tmux show-option -gv @tokyo-night-tmux_path_format 2>/dev/null)
MAX_LENGTH=$(tmux show-option -gv @tokyo-night-tmux_path_max_length 2>/dev/null)

RESET="#[fg=brightwhite,bg=#15161e,nobold,noitalics,nounderscore,nodim]"

# check if not enabled
if [ "${SHOW_PATH}" != "1" ]; then
  exit 0
fi

current_path="${1}"
default_path_format="relative"
PATH_FORMAT="${PATH_FORMAT:-$default_path_format}"
MAX_LENGTH="${MAX_LENGTH:-30}"

# check user requested format
if [[ ${PATH_FORMAT} == "relative" ]]; then
  current_path="$(echo ${current_path} | sed 's#'"$HOME"'#~#g')"
fi

# truncate to max length, showing tail of path
if [[ ${#current_path} -gt ${MAX_LENGTH} ]]; then
  current_path="…${current_path: -$((MAX_LENGTH-1))}"
fi

echo "#[fg=blue,bg=default]░  ${RESET}#[bg=default]${current_path} "
