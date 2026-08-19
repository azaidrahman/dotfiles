# Compile the Swift HUDs on each machine, do not commit the binaries

The karabiner HUD binaries were compiled on one Mac and committed to chezmoi.
Both Macs then got the same artifact. On 19 Aug 2026 we found that all three
binaries carried `minos=26.0`, because onyx runs macOS 26 and compiled them.
aqua runs macOS 15.7.4, so `dyld` refused to load them and every HUD call
failed with exit code 134.

The failure was invisible for months. The Python code catches a failed HUD call
and falls back to an `osascript` dialog, and `notify()` swallows every error, so
aqua showed native dialogs and no toasts at all. The user read this as a styling
difference between the machines.

A compiled binary is specific to one machine. We therefore removed the binaries
from the chezmoi source and added a `run_onchange` script that runs `swiftc`
when a Swift source file changes. Each Mac now builds its own binary against its
own SDK.

## Considered options

- **Pin the deployment target** with `-target arm64-apple-macosx15.0` and keep
  one committed binary. Rejected: it treats the symptom, and it depends on the
  person who compiles remembering the flag every time.

## Consequences

- Both Macs need the Xcode Command Line Tools. The build script skips with a
  message when `swiftc` is absent, so `chezmoi apply` never fails for this.
- The HUD source must not use an API that macOS 15 lacks, or aqua fails to
  compile. The build script reports this at apply time instead of at run time.
