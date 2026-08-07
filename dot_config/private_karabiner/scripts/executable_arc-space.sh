#!/bin/sh
# Focus an Arc space by name.
# Usage: arc-space.sh <space name> | toggle
# "toggle" changes the focus between the "Work" space and the "Research" space.

target="${1:?usage: arc-space.sh <space name>|toggle}"

if [ "$target" = "toggle" ]; then
  current=$(osascript -e 'tell application "Arc" to get title of active space of front window' 2>/dev/null)
  if [ "$current" = "Work" ]; then
    target="Research"
  else
    target="Work"
  fi
fi

osascript <<EOF
tell application "Arc"
  activate
  try
    tell front window to tell space "$target" to focus
  end try
end tell
EOF
