# add-keymap Interactive Wizard — Design

**Date:** 2026-06-07
**Status:** Approved
**Area:** `dot_config/private_karabiner` (goku/Karabiner config)

## Problem

Adding a keymap to a layer today means hand-editing the right YAML file in the
correct format (`key | label | extra`), knowing which file each layer lives in,
remembering the deploy sequence (`./build.sh` → `chezmoi apply` → `goku`), and
manually checking `data/fkey-pool.json` to learn which F-key combo a shortcut-layer
entry was assigned. It is error-prone (key collisions, wrong format, wrong file)
and the F-key assignment feedback loop is opaque.

## Goal

An interactive command-line wizard that walks the user through:

1. Which **layer** to add to.
2. Which **key** to map (with validation + collision detection).
3. The **target** for that key (per-layer prompts).
4. **Installs** it (writes YAML, builds, optionally deploys).
5. **Reports** which key/chord it ended up mapped to — including the auto-assigned
   F-key combo for shortcut-layer pool entries.

Implemented in **Go**, distributed as a **committed compiled binary**.

## Non-Goals (v1, YAGNI)

- No delete / list / rename operations. Add (and overwrite-on-collision) only.
- No TUI framework. Plain stdin prompts, dependency-free.
- No reimplementation of the EDN generator or F-key pool *assignment* logic.

## Layers Covered

| Layer | File / section | Entry shape | "Mapped to" feedback |
|---|---|---|---|
| `app` (Right Opt) | `config/app.yaml` → `app:` | `key \| label \| App` (UPPER key = shift; `!combo` = raw goku) | the key itself |
| `workspace` (Left Opt) | `config/help-text.yaml` → `workspace:` / `workspace-shift:` | `key \| label \| aerospace cmd` | the key (base or +shift) |
| `l1` / `l2` / `l3` | `config/shortcuts.yaml` → `l1:`/`l2:`/`l3:` | `key \| label \| [open:App / !combo / blank]` | **F-key combo from pool** or the direct action |
| `hyper` (CapsLock) | `config/hyperkeys.yaml` → `hyper:` | nested `key: { mod: action # label }` | the hyper+mod+key chord |

## Architecture

### Distribution & layout

- **Source:** `src/add-keymap/` — a Go module:
  - `go.mod`
  - `main.go` — entry point, top-level wizard flow, source-dir resolution.
  - `layers.go` — per-layer prompt logic + key/allowed-set definitions.
  - `yaml.go` — line-based read/collision-scan/append/overwrite for the YAML files.
  - `pool.go` — `FKEY_POOL` + `ALL_MODS` slot→combo render table (mirrors `lib/pool.py`), reads `data/fkey-pool.json`.
  - `deploy.go` — shells out to `./build.sh`, `chezmoi apply`, `goku`.
- **Binary:** built to `scripts/executable_add-keymap`, **committed** (deploys to
  `~/.config/karabiner/scripts/add-keymap`, exactly like the existing
  `executable_time-hud`).
- **Rebuild step:** `src/add-keymap/build.sh` runs
  `go build -o ../../scripts/executable_add-keymap .`. Go is a **build-time-only**
  prerequisite; runtime needs only the binary.

### Single source of truth

The wizard never regenerates EDN or assigns F-key slots. It:

1. Edits the YAML.
2. Shells out to `./build.sh` (the existing Python generator does EDN generation
   **and** F-key pool assignment).
3. Reads back `data/fkey-pool.json` to *report* the slot it was assigned, rendering
   it to a human combo via the small mirrored table in `pool.go`.

Only the slot→combo *render* table is duplicated from `lib/pool.py` (it is small and
stable); a comment in `pool.go` points at the Python source. Pool *allocation* stays
exclusively in Python.

### Source-directory resolution

The wizard operates on the chezmoi **source** karabiner dir (so edits are tracked
and `chezmoi apply` deploys them), not the deployed copy. It resolves the dir via:

```
chezmoi source-path ~/.config/karabiner
```

Fallback: the directory two levels up from the running binary's location. All file
edits and the `./build.sh` invocation happen in the resolved source dir.

## Wizard Flow

1. **Pick layer** — numbered menu: `app · workspace · l1 · l2 · l3 · hyper`.
2. **Pick key (validated):**
   - Allowed set = QWERTY letters/digits/symbols + special names
     (`hyphen`, `equal_sign`, `open_bracket`, `close_bracket`, `semicolon`, `quote`,
     `comma`, `period`, `slash`, `backslash`, `grave_accent_and_tilde`, `space`).
   - For `app`/`workspace`, an uppercase letter denotes the shift variant and is a
     **distinct** key from its lowercase form (matches `make_rule` semantics).
   - **Collision check:** if the key is already mapped in that layer, print its
     current binding and offer `[overwrite / pick another / cancel]`.
3. **Pick target (per layer):**
   - **app:** app name (plain → `open -a "<App>"`) or `!combo` raw goku; + label.
   - **workspace:** base or `+shift` (writes to `workspace:` or `workspace-shift:`)
     → aerospace command + label.
   - **l1/l2/l3:** choose mapping type —
     **(a) F-key pool** (label only; combo auto-assigned on build), or
     **(b) direct action** (`open:App` or `!combo`); + label.
   - **hyper:** pick modifier slot
     `[- · shift · cmd · opt · ctrl · opt+cmd · ctrl+shift]` → action
     (goku key code, or comma-separated sequence rendered as `["a","b","c"]`) + label.
4. **Confirm summary** — layer · key · target · label; `[confirm / cancel]`.
5. **Write YAML** — line-based, preserving comments and grouping:
   - Flat sections (`app`/`workspace`/`workspace-shift`/`l1`/`l2`/`l3`): insert the
     `- key | label | extra` line at the end of that section's item list (before the
     next top-level `key:` header or EOF).
   - **hyper:** if the key block exists, insert `    <mod>: <action> # <label>` after
     its last sub-entry; otherwise insert a new
     `  <key>:\n    <mod>: <action> # <label>` block at the end of the `hyper:`
     section (before `misc:`). 2-space key indent, 4-space sub-entry indent.
   - **Overwrite** replaces the existing line in place.
6. **Build** — run `./build.sh`, streaming generator output; surface any
   "YAML ↔ EDN out of sync" warnings and pool-exhaustion errors.
7. **Report mapping** — for pool entries:
   `l1 + o  →  cmd+F16   (bind this in Alfred/KM)`, read from `data/fkey-pool.json`.
   For direct/app/workspace/hyper: print the resulting chord/action.
8. **Deploy** — prompt `chezmoi apply && goku now? [y/N]`. Never `--force`. On
   confirm, run both and report success; on decline, print the two commands to run.

## Error Checking

- Invalid / unknown key → re-prompt.
- Duplicate key in the layer → overwrite-or-cancel.
- Hyper modifier already used on that key → collision handling (overwrite/cancel).
- Empty label or empty action → re-prompt.
- Light validation: `!combo` must start with `!` and use known modifier letters
  (`C T O S F Q W R P` and `!` / `#`); `open:` target must be non-empty.
- Pool exhaustion surfaced from the generator's `RuntimeError`.
- Non-zero exit from `build.sh` / `chezmoi` / `goku` → stop and show the error.

## Testing

- **Go unit tests** (`*_test.go`) for the pure logic:
  - `yaml.go`: collision scan, append into each flat section, hyper nested insert
    (new key vs. existing key), overwrite-in-place — assert byte-level output against
    fixtures so comments/grouping are provably preserved.
  - `pool.go`: slot→combo rendering for representative slots, cross-checked against
    the values `lib/pool.py` produces for the same slots.
  - key validation + allowed-set / special-name mapping.
- **Manual end-to-end** on a scratch copy of the config dir: add one entry per layer,
  run the full flow, confirm `./build.sh` produces the expected EDN diff and the
  reported F-key combo matches `data/fkey-pool.json`.

## Risks

- **YAML round-trip fidelity** — mitigated by line-based editing (no full
  parse/serialize) plus byte-level fixture tests.
- **Render table drift from `lib/pool.py`** — mitigated by a unit test that pins the
  Go output to known Python-produced values, and a source-pointer comment.
- **Binary staleness** — the committed binary can lag the source; mitigated by the
  documented `src/add-keymap/build.sh` rebuild step and a README note.
