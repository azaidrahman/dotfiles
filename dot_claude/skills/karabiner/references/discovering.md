# Discovering and explaining existing keymaps

The YAML configs are the human-readable source of truth — read them first; don't reverse-engineer bindings from the compiled `karabiner.json`.

## What's bound where

| To see… | Read (in the chezmoi source dir) |
|---------|----------------------------------|
| App launcher (RightOpt) | `config/app.yaml` |
| Workspace / aerospace (LeftOpt) | `config/help-text.yaml` (`workspace:`, `workspace-shift:`) |
| Shortcut layers l1/l2/l3 | `config/shortcuts.yaml` |
| Hyper navigation (CapsLock) | `config/hyperkeys.yaml` |
| Hand-written rules (caps→hyper, Tab→Ctrl, double-tap `\`, layer triggers, ghostty swaps) | `karabiner.base.edn` (rules **outside** the `;; BEGIN … ;; END` markers) |
| The fully merged, compiled-from view | `karabiner.edn` (generated) — or the deployed `~/.config/karabiner/karabiner.edn` |

On the Mac itself: hold a layer and press `/` to pop its help overlay (App = RightOpt+`/`, l1 = Shift+RightOpt+`/`, Workspace = LeftOpt+`/`, Hyper = CapsLock+`/`, etc.).

## Finding a free key in a layer

List the `key` column already used in that layer's YAML — anything not listed is free. The `add-keymap` CLI also validates and refuses a collision (unless `-overwrite`), so a wrong guess fails loudly rather than clobbering.

For **l1/l2/l3** with auto-assigned F-keys, the slot assignments live in `data/fkey-pool.json` (e.g. `"l2:c": 11`). They're persistent — adding a new key takes the next free slot and never reshuffles existing ones. Running `./build.sh` prints the current per-layer key→F-key table.

## Explaining a binding

A Goku rule is `[:from :to :condition {:options}]`. Decode `:from`/`:to` with the modifier legend in `SKILL.md`:

- `:!Cgrave_accent_and_tilde` → mandatory **C**md + `` ` `` (app-switcher).
- `:!QWERh` → right-**hyper** (`Q`+`W`+`E`+`R` = right cmd+ctrl+opt+shift) + `h`.
- `[:slash :show-app-help :app-launch {:afterup :clear-app-help}]` → in the `app-launch` layer, `/` shows the overlay; on key-up it clears.
- Layer triggers set a variable: `[:!Sright_option [["shortcut-l1" 1]] nil {:afterup [["shortcut-l1" 0]]}]` turns the l1 layer on while held; rules guarded by `:shortcut-l1` only fire then.

The shortcut layers map keys to F13/F16–F20 × modifier combos (48 slots) so an external app (Alfred, Keyboard Maestro) can catch the F-key — the EDN side just emits the chord; the *action* lives in that app.

Device `simple_modifications`, `fn_function_keys`, and mouse settings are **not** in any of these files — they're managed in the Karabiner-Elements UI and snapshotted under `data/devices_*.json`.
