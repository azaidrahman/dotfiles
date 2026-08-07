#!/usr/bin/python3
"""Write the study block to Calendar.app.

Calendar.app syncs to Google and Dot.app reads the same store, so this needs no
API credentials.
"""
import subprocess
from datetime import datetime

CALENDAR = "Study"

_CREATE = '''
on run argv
  set t to item 1 of argv
  set m to (item 2 of argv) as integer
  set s to current date
  set e to s + m * minutes
  tell application "Calendar" to tell calendar "%s"
    set ev to make new event with properties {summary:t, start date:s, end date:e}
    return uid of ev
  end tell
end run
''' % CALENDAR

_CANCEL = '''
on run argv
  set u to item 1 of argv
  set t to item 2 of argv
  tell application "Calendar" to tell calendar "%s"
    set matches to (every event whose uid is u)
    if matches is {} then return "missing"
    set ev to item 1 of matches
    set summary of ev to t & " (cancelled)"
    set end date of ev to (current date)
    return "ok"
  end tell
end run
''' % CALENDAR


def _osascript(script: str, *args: str) -> str:
    r = subprocess.run(["osascript", "-", *args], input=script,
                       capture_output=True, text=True, check=True)
    return r.stdout.strip()


def create_event(topic: str, minutes: int) -> str:
    """Make the event and return its UID."""
    return _osascript(_CREATE, topic, str(minutes))


def mark_cancelled(uid: str, topic: str) -> str:
    """Retitle the event and move its end to now. The event is never deleted,
    so a cancelled session stays countable."""
    return _osascript(_CANCEL, uid, topic)
