#!/usr/bin/env python3
"""Shared plumbing for km-apply / km-export.

Keyboard Maestro macros in the Chezmoi-Managed group are versioned as
per-macro XML plist files. See the keyboard-maestro Claude skill for the
workflow.
"""
import plistlib
import re
import subprocess
import sys
import time
from pathlib import Path

GROUP_NAME = "Chezmoi-Managed"
MACROS_DIR = Path.home() / ".config/keyboardmaestro/macros"


def osascript(script: str) -> str:
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"osascript failed: {r.stderr.strip()}")
    return r.stdout.strip()


def check_km_running() -> None:
    probe = f'tell application "Keyboard Maestro" to exists macro group "{GROUP_NAME}"'
    try:
        ok = osascript(probe)
    except RuntimeError as e:
        sys.exit(f"error: cannot talk to Keyboard Maestro editor: {e}")
    if ok == "true":
        return
    # New machine: the group doesn't exist yet. Its UID can't be chosen (KM
    # assigns one on creation), so group_uid() looks it up dynamically —
    # every machine gets its own real UID, and that's fine.
    try:
        osascript(
            f'tell application "Keyboard Maestro" to make new macro group '
            f'with properties {{name:"{GROUP_NAME}"}}'
        )
        time.sleep(2)  # KM's AppleScript layer lags briefly after mutations
    except RuntimeError as e:
        sys.exit(f'error: macro group "{GROUP_NAME}" not found and could not be created: {e}')
    if osascript(probe) != "true":
        sys.exit(f'error: macro group "{GROUP_NAME}" still not found after creating it')


def group_uid() -> str:
    return osascript(f'tell application "Keyboard Maestro" to id of macro group "{GROUP_NAME}"')


def read_macro_file(path: Path) -> dict:
    with open(path, "rb") as f:
        data = plistlib.load(f)
    if not isinstance(data, dict) or "UID" not in data:
        raise ValueError(f"{path.name}: not a macro plist dict with a UID key")
    return data


def find_duplicate_uids(macro_files: list) -> dict:
    """Find each UID that more than one macro file claims.

    Take (filename, macro dict) pairs. Return a map of the repeated UID
    to the sorted names of the files that claim it. An empty map means
    every file has its own UID.

    Keyboard Maestro keys a macro by its UID, so two files with one UID
    are the same macro. An import of the second one replaces the first,
    and the file that the loop reads last wins. The caller must stop
    before it writes, because the result is silent and wrong.
    """
    by_uid = {}
    for name, macro in macro_files:
        by_uid.setdefault(macro["UID"], []).append(name)
    return {uid: sorted(names) for uid, names in by_uid.items() if len(names) > 1}


def wrap_in_group(macro_dicts: list) -> bytes:
    group = {
        "Activate": "Normal",
        "Name": GROUP_NAME,
        "UID": group_uid(),
        "Macros": macro_dicts,
    }
    return plistlib.dumps([group], fmt=plistlib.FMT_XML)


def live_macros() -> dict:
    script = f'''
    tell application "Keyboard Maestro"
        set out to ""
        repeat with m in macros of macro group "{GROUP_NAME}"
            set out to out & (id of m) & "\\t" & (name of m) & linefeed
        end repeat
        return out
    end tell'''
    result = {}
    for line in osascript(script).splitlines():
        if "\t" in line:
            uid, name = line.split("\t", 1)
            result[uid] = name
    return result


def as_literal(s: str) -> str:
    """Escape a string for safe interpolation into an AppleScript string literal."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def slugify(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return s or "macro"
