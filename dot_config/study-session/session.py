#!/usr/bin/python3
"""Start and end a study session."""
import argparse
import json
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path

import note
import outcome
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


def idle_seconds() -> float:
    """Return the seconds since the last key press or mouse move."""
    out = subprocess.run(
        ["ioreg", "-c", "IOHIDSystem"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "HIDIdleTime" in line:
            return int(line.split("=")[-1].strip()) / 1_000_000_000
    return 0.0


def ask_distraction(topic: str):
    """Ask for the score. Return None if the user closes the prompt."""
    script = (
        f'display dialog "How distracted were you during {topic}?\\n'
        '1 is no interruptions. 10 is never more than 15 clear minutes." '
        'default answer "" with title "Study session"')
    r = subprocess.run(["osascript", "-e", script],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    text = r.stdout.strip().split("text returned:")[-1].strip()
    try:
        value = int(text)
    except ValueError:
        return None
    return value if 1 <= value <= 10 else None


def check() -> None:
    if not STATE.exists():
        return
    s = json.loads(STATE.read_text())
    planned_end = datetime.fromisoformat(s["planned_end"])
    start_at = datetime.fromisoformat(s["start"])
    now = datetime.now()

    timer = next((t for t in timers.load() if t["id"] == s["timer_id"]), None)
    if timer is not None and timer["fired_date"] is not None:
        # The plist holds an aware date. Compare in the local naive form.
        timer = {**timer,
                 "fired_date": timer["fired_date"].astimezone().replace(tzinfo=None)}

    status, end_at = outcome.classify(timer, planned_end, now, idle_seconds())
    if status == "running":
        return

    distraction = ask_distraction(s["topic"]) if status == "completed" else None
    if status == "cancelled":
        studycal.mark_cancelled(s["event_uid"], s["topic"])

    path, body = note.build_note(s["topic"], start_at, end_at, status, distraction)
    subprocess.run(["open", note.adv_uri(path, body)], check=True)
    STATE.unlink()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start")
    s.add_argument("--topic", required=True)
    s.add_argument("--minutes", type=int, required=True)
    sub.add_parser("check")
    a = p.parse_args()
    if a.cmd == "start":
        start(a.topic, a.minutes)
    elif a.cmd == "check":
        check()
