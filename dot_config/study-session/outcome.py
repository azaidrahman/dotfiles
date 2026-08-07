#!/usr/bin/python3
"""Decide how a study session ended."""
from datetime import datetime, timedelta

# A fired date must fall near the planned end. Clock.app can hold old timers.
FIRE_WINDOW = timedelta(minutes=5)

# The machine must be idle this long before the session is cancelled. A long
# limit is deliberate. Reading a paper makes no key presses.
IDLE_LIMIT = 2700


def classify(timer, planned_end: datetime, now: datetime,
             idle_seconds: float, idle_limit: int = IDLE_LIMIT):
    """Return the state of the session and the time it ended.

    The states are running, completed, and cancelled.
    """
    if idle_seconds >= idle_limit:
        return "cancelled", now - timedelta(seconds=idle_seconds)

    if timer is None:
        return "cancelled", now

    if timer["state"] >= 2:
        return "running", now

    fired = timer.get("fired_date")
    if fired is not None and abs(fired - planned_end) <= FIRE_WINDOW:
        return "completed", fired

    return "cancelled", now
