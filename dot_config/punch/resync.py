"""Bring this machine back to the chezmoi source.

Chezmoi keeps a hash of every script that it ran. A hook runs again only
when its hash changes, so a machine that drifts out of band stays wrong.
A macro that somebody edited in the Keyboard Maestro window and a HUD
binary that somebody deleted both leave the source hash the same, and an
apply then reports success and changes nothing.

Clear the script state first. Chezmoi holds no hash after that, so every
hook runs again and the machine matches the source.

punch starts this module as its own process. A resync takes minutes, and
the punch HUD closes at once.
"""
import subprocess
import sys
from pathlib import Path

# The HUD binary shows the toast. This module is a leaf, like note and
# outcome, so it holds the path itself instead of importing punch.
HUD = Path.home() / ".config/karabiner/scripts/timer-hud"


def commands() -> list[list[str]]:
    """Return the commands of a resync, in the order that they run.

    The clear comes first. An update that runs first writes the hashes
    again, and every hook stays gated.
    """
    return [
        ["chezmoi", "state", "delete-bucket", "--bucket=scriptState"],
        ["chezmoi", "update"],
    ]


def result_text(code: int) -> str:
    """Return the text of the toast for an exit code."""
    return "resync done" if code == 0 else "resync failed"


def toast(text: str) -> None:
    """Show a small overlay through the HUD binary.

    The toast is a report, so a failure to show it never stops a resync.
    """
    try:
        subprocess.Popen([str(HUD), "toast", text],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def main() -> int:
    """Run a resync and report the result. Return the exit code.

    A command that fails stops the resync. An update that runs after a
    failed clear looks like a success and hides the fault.
    """
    toast("resync started")
    code = 0
    for command in commands():
        r = subprocess.run(command, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stderr, file=sys.stderr, end="")
            code = r.returncode
            break
    toast(result_text(code))
    return code


if __name__ == "__main__":
    sys.exit(main())
