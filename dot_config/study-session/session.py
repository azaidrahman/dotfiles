#!/usr/bin/python3
"""Start and end a study session."""
import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

import note
import outcome
import studycal
import timers

STATE = Path.home() / ".local/state/study-session.json"
SHORTCUT = "Start Study Timer"
TOPICS = Path.home() / "vaults/Polaris/5-Workbook/worklog/Topics.md"
PRESETS = ["25", "50", "60", "90"]


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
    notify(f"{topic} — timer running for {minutes} min")


def read_topics() -> list[str]:
    """Return the topics, with the frontmatter and blank lines removed."""
    lines = TOPICS.read_text().splitlines()
    out, fences = [], 0
    for line in lines:
        if line.strip() == "---" and fences < 2:
            fences += 1
            continue
        if fences < 2 or not line.strip():
            continue
        out.append(line.strip())
    return out


def choose(prompt: str, options: list[str]):
    """Show a native list picker. Return the choice, or None on cancel."""
    safe = [o.replace("\\", "").replace('"', "") for o in options]
    lst = ", ".join(f'"{o}"' for o in safe)
    script = (f'choose from list {{{lst}}} with title "Study session" '
              f'with prompt "{prompt}" default items {{"{safe[0]}"}}')
    r = subprocess.run(["osascript", "-e", script],
                       capture_output=True, text=True)
    out = r.stdout.strip()
    if r.returncode != 0 or out == "false":
        return None
    return out


def ask_text(prompt: str):
    """Show a one-line text dialog. Return the text, or None on cancel."""
    script = (f'display dialog "{prompt}" default answer "" '
              'with title "Study session"')
    r = subprocess.run(["osascript", "-e", script],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return r.stdout.strip().split("text returned:")[-1].strip() or None


def start_interactive() -> None:
    """Ask for the topic and the minutes, then start the session."""
    if STATE.exists():
        notify("A session is already open. Cancel its timer first.")
        return

    topic = choose("What are you studying?", read_topics() + ["other…"])
    if topic is None:
        return
    if topic == "other…":
        topic = ask_text("New topic:")
        if topic is None:
            return
        with TOPICS.open("a") as f:
            if TOPICS.read_bytes()[-1:] not in (b"\n", b""):
                f.write("\n")
            f.write(topic + "\n")

    minutes = choose("For how long?", PRESETS + ["custom…"])
    if minutes is None:
        return
    if minutes == "custom…":
        minutes = ask_text("Minutes:")
        if minutes is None:
            return
    try:
        m = int(minutes)
    except ValueError:
        notify(f"Not a number: {minutes}")
        return
    start(topic, m)


HUD = Path.home() / ".config/karabiner/scripts/timer-hud"


def notify(text: str) -> None:
    """Show a small overlay through the karabiner HUD binary.

    Notification Center drops both the osascript and the Keyboard
    Maestro notifications on this machine, so the HUD shows a toast
    instead. Failures never block the session.
    """
    try:
        subprocess.Popen([str(HUD), "toast", text],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


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

    # Atomically claim the session so a second check() run (e.g. launchd
    # firing again while a distraction dialog is still open) skips it
    # instead of opening a second dialog and writing a duplicate note.
    claimed = STATE.with_suffix(".ending.json")
    try:
        STATE.rename(claimed)
    except FileNotFoundError:
        return

    try:
        s = json.loads(claimed.read_text())
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
            # Not actually done yet. Release the claim for the next run.
            claimed.rename(STATE)
            return

        distraction = ask_distraction(s["topic"]) if status == "completed" else None
        path, body = note.build_note(s["topic"], start_at, end_at, status, distraction)
    except Exception:
        # Something failed mid-way, before any side effect ran. Put the
        # state file back so the next minute's check() retries.
        claimed.rename(STATE)
        raise

    # From here on, side effects begin. The claim must not go back to
    # STATE, or a failure here would cause a retry and a duplicate note.
    claimed.unlink()

    if status == "cancelled":
        try:
            result = studycal.mark_cancelled(s["event_uid"], s["topic"])
            if result == "missing":
                print(f"warning: calendar event {s['event_uid']} not found",
                      file=sys.stderr)
        except Exception as e:
            print(f"warning: mark_cancelled failed: {e}", file=sys.stderr)

    try:
        subprocess.run(["open", note.adv_uri(path, body)], check=True)
    except Exception as e:
        print(f"warning: failed to open note: {e}", file=sys.stderr)

    hours = round((end_at - start_at).total_seconds() / 3600, 2)
    if status == "completed":
        notify(f"{s['topic']} completed — {hours} h logged")
    elif status == "cancelled":
        notify(f"{s['topic']} cancelled — {hours} h logged")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start")
    s.add_argument("--topic", required=True)
    s.add_argument("--minutes", type=int, required=True)
    sub.add_parser("start-interactive")
    sub.add_parser("check")
    a = p.parse_args()
    if a.cmd == "start":
        start(a.topic, a.minutes)
    elif a.cmd == "start-interactive":
        start_interactive()
    elif a.cmd == "check":
        check()
