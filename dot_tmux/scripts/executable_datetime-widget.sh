#!/usr/bin/env bash

# Custom datetime widget with concise DD/MM/YY date format (update-safe).
# Forked from tokyo-night-tmux because the plugin only offers DMY/MDY/YMD
# with `-` separators and a 4-digit year; we want 13/06/26.

# Check if enabled
ENABLED=$(tmux show-option -gv @tokyo-night-tmux_show_datetime 2>/dev/null)
[[ ${ENABLED} -ne 1 ]] && exit 0

# Theme colors come from the upstream plugin (absolute path; stable across updates)
PLUGIN_DIR="$HOME/.tmux/plugins/tokyo-night-tmux/src"
. "$PLUGIN_DIR/../lib/coreutils-compat.sh"
source "$PLUGIN_DIR/themes.sh"

time_format=$(tmux show-option -gv @tokyo-night-tmux_time_format 2>/dev/null)

# Concise day/month/2-digit-year
date_string="%d/%m/%y"

if [[ $time_format == "12H" ]]; then
  time_string="%I:%M %p"
elif [[ $time_format == "hide" ]]; then
  time_string=""
else
  time_string="%H:%M"
fi

separator=""
if [[ $date_string && $time_string ]]; then
  separator="❬ "
fi

date_string="$(date +"$date_string")"
time_string="$(date +"$time_string")"

echo "$RESET#[fg=${THEME[foreground]},bg=${THEME[bblack]}] $date_string $separator$time_string "
