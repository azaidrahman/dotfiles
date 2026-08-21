#!/usr/bin/python3
"""Pure time logic for the retroactive start. No I/O lives here."""
from __future__ import annotations

from datetime import datetime, timedelta


def round_down_quarter(now: datetime) -> datetime:
    """Round down to the nearest 15 minutes, for the time field prefill."""
    return now.replace(minute=now.minute - now.minute % 15,
                       second=0, microsecond=0)


def to_12h(dt: datetime) -> tuple:
    """Return (hour12, minute, am|pm) for the three HUD fields."""
    hour = dt.hour % 12 or 12
    return hour, dt.minute, "pm" if dt.hour >= 12 else "am"


def classify(start: datetime, minutes: int, now: datetime) -> tuple:
    """Decide the branch for a backdated start.

    Return ('live', remaining_minutes) when the timebox still has more than
    one minute to run, else ('retro', end). A remainder under one minute is
    not worth a timer.
    """
    planned_end = start + timedelta(minutes=minutes)
    remaining = (planned_end - now).total_seconds()
    if remaining > 60:
        return "live", round(remaining / 60)
    return "retro", planned_end


def parse_note(text: str, day) -> tuple | None:
    """Read the start and the end from the frontmatter of a session note."""
    start = end = None
    for line in text.splitlines():
        if line.startswith("start:"):
            start = line.split(":", 1)[1].strip().strip('"')
        elif line.startswith("end:"):
            end = line.split(":", 1)[1].strip().strip('"')
    if not start or not end:
        return None
    try:
        s = datetime.combine(day, datetime.strptime(start, "%H:%M").time())
        e = datetime.combine(day, datetime.strptime(end, "%H:%M").time())
    except ValueError:
        return None
    return s, e


def find_overlap(start: datetime, end: datetime, notes: list) -> str | None:
    """Return 'HH:MM Topic' of the first note that the block overlaps.

    A shared edge is not an overlap — back-to-back blocks are the normal
    case, not a conflict.
    """
    for topic, s, e in notes:
        if start < e and s < end:
            return f"{s:%H:%M} {topic}"
    return None
