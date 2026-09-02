---
name: keyboard-maestro
description: Use when working with this Mac's Keyboard Maestro macro sync — adding, editing, or removing a macro, inspecting live macro state, or capturing GUI-made edits back into chezmoi. Symptoms include "keyboard maestro", "KM macro", "add/edit/remove a macro", editing a `.kmmacros` file, or `km-apply` / `km-export`.
---

# Keyboard Maestro macro sync

Keyboard Maestro macros in the **Chezmoi-Managed** group are file-managed, one macro per file, and kept in sync with chezmoi the same way Karabiner's config is: edit the source, apply, verify. Everything outside that group is left alone.

## The one rule that prevents breakage

**Never invent or reuse a UID for an existing macro, and never import a macro file by hand.** The `UID` key inside a macro's plist dict is authoritative — Keyboard Maestro identifies macros by UID, not by filename or name. Manual imports of an existing UID create a **duplicate under a new UID** instead of replacing it; the sync tooling always deletes the old macro first before importing. Let `km-apply` do the import.

## Where things live

- **Edit here (chezmoi source):** `dot_config/keyboardmaestro/exact_macros/*.kmmacros`
- **Deployed:** `~/.config/keyboardmaestro/macros/*.kmmacros`
- Each file is a single macro as a plist `dict`. The filename is a cosmetic kebab-case slug for humans — renaming the file does nothing to Keyboard Maestro. The `UID` key inside the plist is what actually identifies the macro.
- Macro group: **"Chezmoi-Managed"**. Only macros in this group are file-managed; macros elsewhere are untouched by any of this tooling. The group's UID differs per machine — `km-apply` looks it up by name at runtime (`kmlib.group_uid()`) rather than hardcoding one, and creates the group automatically on a machine where it doesn't exist yet.

## Edit flow (chezmoi source → live)

1. Edit the XML in the chezmoi source (`dot_config/keyboardmaestro/exact_macros/<slug>.kmmacros`).
2. `chezmoi apply` — this triggers a `run_onchange` hook that runs `~/.config/keyboardmaestro/bin/km-apply` automatically, which deletes the old macro (by UID) and re-imports the new one.
3. Verify the change landed:
   ```bash
   osascript -e 'tell application "Keyboard Maestro" to name of every macro of macro group "Chezmoi-Managed"'
   ```

**If Keyboard Maestro Engine isn't running, the `run_onchange` hook skips silently (exit 0)** — nothing gets applied and chezmoi won't complain. After starting KM, run `~/.config/keyboardmaestro/bin/km-apply` manually to catch up.

## Adding a new macro

- Generate a fresh UID with `uuidgen` — never reuse or invent one, and never copy a UID from an existing macro.
- Write the new `.kmmacros` file as a single-macro plist dict in the chezmoi source, then follow the edit flow above.
- Remember: imports must be **group-wrapped** XML (an array of macro dicts under a macro group), not a bare macro dict — Keyboard Maestro silently ignores a plain macro-array import that isn't wrapped in a group.

## Capturing GUI-made edits (export)

If a macro was edited by hand in the Keyboard Maestro Editor, capture it back into chezmoi rather than letting source and live state drift:

```bash
~/.config/keyboardmaestro/bin/km-export
```

- Writes the current live XML for each Chezmoi-Managed macro back into the chezmoi source dir.
- Strips `CreationDate` / `ModificationDate` so diffs stay clean (those fields churn on every KM save and aren't meaningful).
- **Refuses to overwrite a file that has uncommitted git changes**, to avoid silently discarding in-progress source edits — pass `--force` to override.
- After exporting: `chezmoi apply` (no-op if content matches) then commit the change.

## Inspecting live state

Read a macro's current XML straight from Keyboard Maestro (useful before editing, or to diff against the chezmoi source):

```bash
osascript -e 'tell application "Keyboard Maestro" to xml of macro id "<uid>"'
```

Note: the `xml` property is **read-only** — you cannot `set xml of macro id ...` to push a change; edits only take effect through delete + import (i.e. the edit flow above).

Other useful live operations via `osascript`:
```applescript
tell application "Keyboard Maestro" to deleteMacro "<uid>"
tell application "Keyboard Maestro" to setMacroEnable "<uid>" enable false
tell application "Keyboard Maestro" to set name of macro id "<uid>" to "<new name>"
```

For the full scriptable surface, see the sdefs:
- `/Applications/Keyboard Maestro.app/Contents/Resources/en.lproj/Editor.sdef`
- `/Applications/Keyboard Maestro.app/Contents/MacOS/Keyboard Maestro Engine.app/Contents/Resources/en.lproj/Engine.sdef`

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Imported a macro file manually over an existing UID | Creates a duplicate under a new UID — delete the duplicate, let `km-apply` do delete-then-import instead |
| Imported a bare macro dict, not group-wrapped | Keyboard Maestro silently ignores it — wrap in a macro group array |
| Tried to `set xml of macro id ...` | `xml` is read-only — go through the edit flow (delete + import), not a direct property set |
| Edited a macro outside "Chezmoi-Managed" via files | Only that group is file-managed; leave other macros to the GUI |
| Assumed the run_onchange hook always ran `km-apply` | It skips (exit 0) when KM Engine isn't running — run `km-apply` manually after starting KM |
| A macro shows disabled instead of gone after a sync | Stray macros in the group get **disabled**, not deleted — this is expected, not a bug |
| Touched `~/.config/keyboardmaestro/Keyboard Maestro Macros.kmsync` | That's Keyboard Maestro's own binary sync file — never edit or touch it |
| `error: macro group "Chezmoi-Managed" not found` on a new machine | Shouldn't happen anymore — `km-apply` auto-creates the group. If it does, KM's `make new macro group` may have failed silently; check KM is actually running and retry |
