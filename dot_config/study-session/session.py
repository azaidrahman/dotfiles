#!/usr/bin/python3
"""Start and end a study session."""
import argparse
import json
import logging
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path

import note
import outcome
import studycal
import timers

log = logging.getLogger("study-session")

LOG_PATH = Path.home() / ".local/state/study-session.log"
STATE = Path.home() / ".local/state/study-session.json"
# check() renames STATE to this while it ends the session. A crash during
# the distraction dialog can leave the claim behind, so every reader looks
# at both files.
CLAIM = STATE.with_suffix(".ending.json")
SHORTCUT = "Start Study Timer"
TOPICS = Path.home() / "vaults/Polaris/5-Workbook/worklog/Topics.md"
PRESETS = ["25", "50", "60", "90"]

# The HUD binary shows the toast, the list picker, and the score picker.
# It reads one key press, so the pickers need no mouse.
HUD = Path.home() / ".config/karabiner/scripts/timer-hud"

# The distraction dialog closes itself after this many seconds, so a timer
# that rings at an empty desk never blocks the next session.
DIALOG_TIMEOUT = 180

# The score a session takes when nobody answers the distraction dialog.
AWAY_DISTRACTION = 5


def open_state():
    """Return the path and the content of the open session, or None."""
    for path in (STATE, CLAIM):
        try:
            return path, json.loads(path.read_text())
        except FileNotFoundError:
            continue
    return None


def _start_timer(minutes: int) -> None:
    url = (f"shortcuts://run-shortcut?name={SHORTCUT.replace(' ', '%20')}"
           f"&input=text&text={minutes}")
    subprocess.run(["open", url], check=True)


def start(topic: str, minutes: int) -> None:
    if open_state() is not None:
        raise SystemExit("A session is already open. Run 'session.py reset' first.")

    before = {t["id"] for t in timers.active(timers.load())}
    _start_timer(minutes)
    now = datetime.now()
    log.info("timer requested: topic=%r minutes=%d", topic, minutes)

    # The timer above is already running. Everything past this point can
    # still fail, so a failure here must be loud — a silent one leaves the
    # timer running with no session to log it.
    try:
        # Give the Shortcuts app time to write the plist.
        timer_id = ""
        for _ in range(20):
            time.sleep(1)
            new = [t for t in timers.active(timers.load()) if t["id"] not in before]
            if new:
                timer_id = new[0]["id"]
                break
        if not timer_id:
            raise RuntimeError(
                "the timer never showed up in the Clock.app plist. Check "
                f"that the shortcut '{SHORTCUT}' exists on this machine.")

        uid = studycal.create_event(topic, minutes)
    except Exception as e:
        log.error("session tracking failed after the timer started: %s",
                   e, exc_info=True)
        notify(f"{topic} timer is running, but session logging failed — "
               "see study-session.log")
        raise

    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps({
        "topic": topic,
        "start": now.isoformat(),
        "planned_end": (now + timedelta(minutes=minutes)).isoformat(),
        "minutes": minutes,
        "timer_id": timer_id,
        "event_uid": uid,
    }, indent=2))
    log.info("session started: topic=%r minutes=%d timer_id=%s event_uid=%s",
              topic, minutes, timer_id, uid)
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


def parse_pick(out: str, options: list[str]):
    """Read the chosen option from the HUD.

    The HUD prints the index of the option. It prints skip when the user
    cancels, and timeout when nobody answers. Both give no choice, because
    a session must never start on its own.
    """
    try:
        index = int(out.strip())
    except ValueError:
        return None
    return options[index] if 0 <= index < len(options) else None


def choose_hud(prompt: str, options: list[str], select: int = 0):
    """Show the HUD list picker. Return the choice, or None on cancel."""
    r = subprocess.run([str(HUD), "pick", "--select", str(select), prompt, *options],
                       capture_output=True, text=True, timeout=300)
    if r.returncode != 0:
        raise RuntimeError(f"the HUD failed: {r.stderr.strip()}")
    return parse_pick(r.stdout, options)


def choose(prompt: str, options: list[str], select: int = 0):
    """Ask the user to choose one option.

    The HUD answers on one key press. A machine with no HUD binary falls
    back to the native picker.
    """
    if HUD.exists():
        try:
            return choose_hud(prompt, options, select)
        except Exception as e:
            log.warning("the pick HUD failed: %s", e)
    return choose_native(prompt, options)


def choose_native(prompt: str, options: list[str]):
    """Show a native list picker. Return the choice, or None on cancel."""
    safe = [o.replace("\\", "").replace('"', "") for o in options]
    lst = ", ".join(f'"{o}"' for o in safe)
    script = ('tell application "System Events"\n'
              'activate\n'
              f'choose from list {{{lst}}} with title "Study session" '
              f'with prompt "{prompt}" default items {{"{safe[0]}"}}\n'
              'end tell')
    r = subprocess.run(["osascript", "-e", script],
                       capture_output=True, text=True)
    out = r.stdout.strip()
    if r.returncode != 0 or out == "false":
        return None
    return out


def ask_text_native(prompt: str):
    """Show a one-line text dialog. Return the text, or None on cancel."""
    script = ('tell application "System Events"\n'
              'activate\n'
              f'display dialog "{prompt}" default answer "" '
              'with title "Study session"\n'
              'end tell')
    r = subprocess.run(["osascript", "-e", script],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return r.stdout.strip().split("text returned:")[-1].strip() or None


def ask_text(prompt: str, digits: bool = False):
    """Ask for one line of text. Return the text, or None on cancel.

    The digits variant refuses every key that is not a digit, so a custom
    timebox can no longer abort the flow on a value like '9o'.
    """
    if HUD.exists():
        try:
            r = subprocess.run([str(HUD), "digits" if digits else "text", prompt],
                               capture_output=True, text=True, timeout=300)
            if r.returncode == 0:
                return r.stdout.strip() or None
            return None
        except Exception as e:
            log.warning("the text HUD failed: %s", e)
    return ask_text_native(prompt)


def start_interactive() -> None:
    """Ask for the topic and the minutes, then start the session."""
    # An open session blocks a new one. Offer to close it instead of only
    # refusing, so a session that nobody ended is never a dead end.
    if open_state() is not None and reset() == "keep":
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
        minutes = ask_text("Minutes:", digits=True)
        if minutes is None:
            return
    try:
        m = int(minutes)
    except ValueError:
        notify(f"Not a number: {minutes}")
        return
    start(topic, m)


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


def parse_distraction(out: str):
    """Read the score from the result of the distraction dialog.

    Return None when the answer is not a score from 1 to 10. A dialog that
    closed itself takes the default score, because an empty desk means the
    session ran without the user in it.
    """
    if "gave up:true" in out:
        return AWAY_DISTRACTION
    text = out.split("text returned:")[-1].split(", gave up:")[0].strip()
    try:
        value = int(text)
    except ValueError:
        return None
    return value if 1 <= value <= 10 else None


def parse_score(out: str):
    """Read the score from the HUD.

    The HUD prints the score, skip, or timeout. Return None when there is
    no score, and the default score when nobody answered.
    """
    text = out.strip()
    if text == "timeout":
        return AWAY_DISTRACTION
    try:
        value = int(text)
    except ValueError:
        return None
    return value if 1 <= value <= 10 else None


def ask_distraction_dialog(topic: str):
    """Ask for the score in a text dialog. This is the fallback for a
    machine that has no HUD binary."""
    script = (
        'tell application "System Events"\n'
        'activate\n'
        f'display dialog "How distracted were you during {topic}?\\n'
        '1 is no interruptions. 10 is never more than 15 clear minutes." '
        'default answer "" with title "Study session" '
        f'giving up after {DIALOG_TIMEOUT}\n'
        'end tell')
    r = subprocess.run(["osascript", "-e", script],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return parse_distraction(r.stdout.strip())


def ask_distraction(topic: str):
    """Ask for the score. Return None if the user skips the prompt.

    The HUD answers on one key press, so the user never needs the mouse.
    """
    if not HUD.exists():
        return ask_distraction_dialog(topic)
    try:
        r = subprocess.run([str(HUD), "score", topic, str(DIALOG_TIMEOUT)],
                           capture_output=True, text=True,
                           timeout=DIALOG_TIMEOUT + 30)
    except Exception as e:
        log.warning("the score HUD failed: %s", e)
        return ask_distraction_dialog(topic)
    if r.returncode != 0:
        return ask_distraction_dialog(topic)
    return parse_score(r.stdout)


def ask_open_session(s: dict) -> str:
    """Ask what to do with a session that is still open.

    The return key takes 'End & log', which is the safe and common answer.
    Escape and a timeout return keep, so a closed prompt never destroys an
    open session.
    """
    start_at = datetime.fromisoformat(s["start"])
    prompt = f"{s['topic']} is still open — {start_at:%H:%M}, {s['minutes']} min"
    choice = choose(prompt, ["End & log", "Keep it", "Discard"])
    return {"End & log": "end", "Discard": "discard"}.get(choice, "keep")


def finish(s: dict, status: str, end_at: datetime, distraction) -> None:
    """Write the note, close the calendar event, and tell the user.

    Every failure is reported and then passed over. The state file is gone
    by this point, so a failure here must not stop the rest of the work.
    """
    start_at = datetime.fromisoformat(s["start"])
    path, body = note.build_note(s["topic"], start_at, end_at, status, distraction)

    if status == "cancelled":
        try:
            result = studycal.mark_cancelled(s["event_uid"], s["topic"])
            if result == "missing":
                log.warning("calendar event %s not found", s["event_uid"])
        except Exception as e:
            log.warning("mark_cancelled failed: %s", e)

    try:
        subprocess.run(["open", note.adv_uri(path, body)], check=True)
    except Exception as e:
        log.warning("failed to open note: %s", e)

    hours = round((end_at - start_at).total_seconds() / 3600, 2)
    log.info("session %s: topic=%r hours=%s", status, s["topic"], hours)
    notify(f"{s['topic']} {status} — {hours} h logged")


def reset() -> str:
    """Deal with a session that is still open.

    Return end, discard, or keep. The state file is gone after end and
    after discard, so the caller can start a new session.
    """
    found = open_state()
    if found is None:
        notify("No session is open.")
        return "keep"

    path, s = found
    choice = ask_open_session(s)
    if choice == "keep":
        return "keep"

    path.unlink()
    if choice == "discard":
        log.info("session discarded: topic=%r", s["topic"])
        notify(f"{s['topic']} discarded — nothing logged")
        return "discard"

    planned_end = datetime.fromisoformat(s["planned_end"])
    finish(s, "cancelled", min(datetime.now(), planned_end), None)
    return "end"


def check() -> None:
    if not STATE.exists():
        return

    # Atomically claim the session so a second check() run (e.g. launchd
    # firing again while a distraction dialog is still open) skips it
    # instead of opening a second dialog and writing a duplicate note.
    claimed = CLAIM
    try:
        STATE.rename(claimed)
    except FileNotFoundError:
        return

    try:
        s = json.loads(claimed.read_text())
        planned_end = datetime.fromisoformat(s["planned_end"])
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
    except Exception:
        # Something failed mid-way, before any side effect ran. Put the
        # state file back so the next minute's check() retries.
        log.error("check failed, will retry next run", exc_info=True)
        claimed.rename(STATE)
        raise

    # From here on, side effects begin. The claim must not go back to
    # STATE, or a failure here would cause a retry and a duplicate note.
    claimed.unlink()
    finish(s, status, end_at, distraction)


if __name__ == "__main__":
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename=LOG_PATH, level=logging.INFO,
                         format="%(asctime)s %(levelname)s %(message)s")

    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start")
    s.add_argument("--topic", required=True)
    s.add_argument("--minutes", type=int, required=True)
    sub.add_parser("start-interactive")
    sub.add_parser("check")
    sub.add_parser("reset")
    a = p.parse_args()
    if a.cmd == "start":
        start(a.topic, a.minutes)
    elif a.cmd == "start-interactive":
        start_interactive()
    elif a.cmd == "check":
        check()
    elif a.cmd == "reset":
        print(reset())
