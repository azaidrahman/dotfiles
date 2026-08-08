#!/bin/sh
# Focus an Arc space by name.
# Usage: arc-space.sh <space name>
#
# If a window already shows the space, the script brings that window to the
# front. If no window shows the space, the script changes the space of the
# front window.

target="${1:?usage: arc-space.sh <space name>}"

osascript - "$target" <<'EOF'
on run argv
  set target to item 1 of argv
  tell application "Arc"
    activate
    set winCount to count of windows
    repeat with i from 1 to winCount
      set w to window i
      try
        if title of active space of w is target then
          if i > 1 then
            set wName to name of w
            tell application "System Events" to tell process "Arc"
              try
                perform action "AXRaise" of (first window whose name is wName)
              end try
            end tell
          end if
          return
        end if
      end try
    end repeat
    try
      tell front window to tell space target to focus
    end try
  end tell
end run
EOF
