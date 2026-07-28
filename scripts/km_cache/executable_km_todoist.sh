#!/usr/bin/env bash

# THRESHOLD=10800  # 3 hours in seconds

# ====TEST====== #
# THRESHOLD=5
# ====TEST====== #

LOCATION=~/scripts/km_cache/km_todoist_last_seen.txt

NOW=$(date +%s)

# Get last Todoist seen time
if [ -f "$LOCATION" ]; then
    TODOIST_TIME=$(cat "$LOCATION")
else
    TODOIST_TIME=0
fi

ELAPSED=$(( NOW - TODOIST_TIME ))
ELAPSED_HOURS=$(( ELAPSED / 60 / 60 ))
ELAPSED_MINUTES=$(( ( ELAPSED / 60 )  % 60 ))
# echo "$ELAPSED_MINUTES"
# printf "ELAPSED: %s\n" "$ELAPSED"

printf "%02d hours %02s minutes" "$ELAPSED_HOURS" "$ELAPSED_MINUTES"

# if [ "$ELAPSED" -ge "$THRESHOLD" ]; then
# else
#     return
# fi
