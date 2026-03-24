#!/bin/bash
# Usage: cycle-or-open.sh "AppName"
# If the app is frontmost, cycle its windows with Cmd+`
# Otherwise, activate the app

APP_NAME="$1"

if [ -z "$APP_NAME" ]; then
    echo "Usage: cycle-or-open.sh \"AppName\""
    exit 1
fi

FRONT_APP=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true')

if [ "$FRONT_APP" = "$APP_NAME" ]; then
    osascript -e 'tell application "System Events" to keystroke "`" using command down'
else
    open -a "$APP_NAME"
fi
