#!/usr/bin/python3
"""Start and end a study session."""
import argparse
import json
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path

import studycal
import timers

STATE = Path.home() / ".local/state/study-session.json"
SHORTCUT = "Start Study Timer"


def _start_timer(minutes: int) -> None:
    url = (f"shortcuts://run-shortcut?name={SHORTCUT.replace(' ', '%20')}"
           f"&input=text&text={minutes}")
    subprocess.run(["open", url], check=True)


def start(topic: str, minutes: int) -> None:
    if STATE.exists():
        raise SystemExit("A session is already open. Cancel its timer first.")

    before = {t["id"] for t in timers.active(timers.load())}
    _start_timer(minutes)

    # Give the Shortcuts app time to write the plist.
    timer_id = ""
    for _ in range(10):
        time.sleep(1)
        new = [t for t in timers.active(timers.load()) if t["id"] not in before]
        if new:
            timer_id = new[0]["id"]
            break
    if not timer_id:
        raise SystemExit(
            "The timer did not start. Check that the shortcut "
            f"'{SHORTCUT}' exists on this machine.")

    now = datetime.now()
    uid = studycal.create_event(topic, minutes)
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps({
        "topic": topic,
        "start": now.isoformat(),
        "planned_end": (now + timedelta(minutes=minutes)).isoformat(),
        "minutes": minutes,
        "timer_id": timer_id,
        "event_uid": uid,
    }, indent=2))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start")
    s.add_argument("--topic", required=True)
    s.add_argument("--minutes", type=int, required=True)
    a = p.parse_args()
    if a.cmd == "start":
        start(a.topic, a.minutes)
