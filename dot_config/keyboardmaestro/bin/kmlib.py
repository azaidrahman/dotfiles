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
from pathlib import Path

GROUP_NAME = "Chezmoi-Managed"
GROUP_UID = "5B7A1F9C-CHEZMOI-TOPBAR-GROUP-00000001"
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
    if ok != "true":
        sys.exit(f'error: macro group "{GROUP_NAME}" not found in Keyboard Maestro')


def read_macro_file(path: Path) -> dict:
    with open(path, "rb") as f:
        data = plistlib.load(f)
    if not isinstance(data, dict) or "UID" not in data:
        raise ValueError(f"{path.name}: not a macro plist dict with a UID key")
    return data


def wrap_in_group(macro_dicts: list) -> bytes:
    group = {
        "Activate": "Normal",
        "Name": GROUP_NAME,
        "UID": GROUP_UID,
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
