# Adding, changing, and removing keymaps

**Prefer the `add-keymap` CLI.** It validates the key, checks for collisions, writes the correct YAML, runs `./build.sh`, prints the resulting mapping, and (with `-deploy`) applies + recompiles. Hand-editing YAML is the fallback.

## `add-keymap` CLI

Binary (no runtime deps):
- Source: `~/.local/share/chezmoi/dot_config/private_karabiner/scripts/executable_add-keymap`
- Deployed: `~/.config/karabiner/scripts/add-keymap`

Either works — both resolve the chezmoi **source** dir via `chezmoi source-path` and edit there. (Override with `ADDKEYMAP_SOURCE=/path` for tests.) **For agents, always use one-liner mode** (pass `-layer`) — bare invocation starts an interactive wizard that will hang a non-interactive session.

```
-layer    app | workspace | l1 | l2 | l3 | hyper      (required)
-key      letter/digit, or one of - = [ ] ; ' , . / \ ` space
          (app/workspace: an UPPERCASE letter = the shift variant)
-label    short overlay label                          (required)
-action   target — semantics depend on layer (see below)
-mod      hyper only: -  shift  cmd  opt  ctrl  opt+cmd  ctrl+shift   (default -)
-shift    workspace only: write the opt+shift variant
-overwrite  replace an existing mapping instead of erroring on collision
-deploy   run "chezmoi apply && goku" after building (default: build only)
```

`-action` by layer:
- **app** — app name for `open -a` (e.g. `Spotify`), or a `!gokuCombo`.
- **workspace** — an aerospace command (e.g. `"workspace 1"`, `"move left"`); add `-shift` for the opt+shift variant.
- **l1 / l2 / l3** — **omit** to get an auto-assigned F-key combo (bind that combo later in Alfred/Keyboard Maestro), or `open:App`, or a `!gokuCombo`.
- **hyper** — a goku key code or comma-separated sequence (required), placed under `-mod`.

### Examples

```bash
add-keymap -layer app -key z -label spotify -action Spotify           # RightOpt+z → Spotify
add-keymap -layer app -key V -label arc -action Arc                   # uppercase = RightOpt+Shift+V
add-keymap -layer l2 -key g -label gemini                             # auto F-key pool slot
add-keymap -layer l1 -key d -label dots -action open:Finder
add-keymap -layer workspace -key h -label 'mv←' -action 'move left' -shift
add-keymap -layer hyper -key m -mod cmd -label spot -action '!Cspacebar'
add-keymap -layer l3 -key '[' -label prev -action '!Sf13' -overwrite -deploy
```

On a collision it errors unless `-overwrite` is given.

**In an agent / non-interactive session, prefer build-only over `-deploy`.** `-deploy` runs a *global* `chezmoi apply` that can trigger unrelated `run_onchange` scripts (e.g. `brew-bundle`) which prompt on a TTY and abort the whole apply before goku runs — leaving the CLI's `✓ Mapped` printed but `karabiner.json` un-recompiled (binding NOT live). Instead, omit `-deploy` and finish by hand:

```bash
chezmoi apply ~/.config/karabiner                                  # targeted: skips brew-bundle etc.
GOKU_EDN_CONFIG_FILE="$HOME/.config/karabiner/karabiner.edn" goku  # always recompile explicitly
grep '<AppName>' ~/.config/karabiner/karabiner.json                # verify it compiled
```

Collision detection is **per-key, not per-target**: it stops you reusing a key, but won't warn if the same app/action is already bound to a *different* key. If you might be duplicating an existing binding, glance at the layer's YAML first (see `discovering.md`).

## Manual YAML path (fallback)

Edit the source file for the layer (see the layer map in `SKILL.md`), then deploy. Each entry is `key | label | target`.

```yaml
# config/app.yaml      RightOpt+z → Spotify
app:
  - z | spotify | Spotify

# config/shortcuts.yaml   l2+d → direct action (or omit 3rd field for an auto F-key)
l2:
  - d | dots | open:Finder

# config/help-text.yaml   LeftOpt+r → resize  (and the opt+shift variant)
workspace:
  - r | +w | resize smart +50
workspace-shift:
  - r | mvR | move right
```

Then:

```bash
cd ~/.local/share/chezmoi/dot_config/private_karabiner
./build.sh && chezmoi apply
```

## Removing or editing a binding

There is no CLI remove. To remove, delete the entry's line from its YAML file; to change it, edit the line (or re-run `add-keymap … -overwrite`). Then `./build.sh && chezmoi apply`. For l1/l2/l3 the freed F-key slot stays reserved in `data/fkey-pool.json` so other keys don't reshuffle — that's intentional.

## After any change

- The CLI prints the final mapping (key → F-key combo or action). Trust that over guessing.
- To verify by hand: `grep` your target in the deployed `~/.config/karabiner/karabiner.json` — the file Karabiner actually loads. If it's only in `karabiner.edn` but not the `.json`, goku hasn't recompiled yet. Or open the layer on the Mac and press `/` to see the help overlay.
- **Never** edit `karabiner.edn` / `karabiner.json` to "fix up" the result — change the YAML and rebuild.
