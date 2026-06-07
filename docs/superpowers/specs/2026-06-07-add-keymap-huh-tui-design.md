# add-keymap: huh TUI refactor

**Date:** 2026-06-07
**Status:** Approved

## Problem

The `add-keymap` wizard's interactive path is hand-rolled `bufio` prompting
(`askMenu` makes you type a list number; `askText` re-prompts on error; no
arrow-key navigation, no inline validation). It works but feels clunky. The
non-interactive flag mode (`-layer …`) is fine and stays as-is.

## Goal

Replace only the interactive path with [`charmbracelet/huh`](https://github.com/charmbracelet/huh)
forms — arrow-key selects, inline validation, live free-key hints — without
touching the flag mode, the YAML-editing logic, or the existing tests.

## Decisions

- **Structure:** sequential `huh` forms. One form picks the layer; Go branches
  to a per-layer detail form; confirm fields gate writes and deploy. Branching
  stays in plain Go (clearer and more testable than one giant dynamic form).
- **Collisions:** the key `Input` *allows* an already-mapped key (format-only
  `Validate`); its Description lists the free keys for the section as a hint. A
  colliding key triggers a follow-up `huh.Confirm` "overwrite?" that gates the
  write — preserving today's overwrite escape hatch with live feedback.
- **Theme:** default Charm theme (no custom lipgloss styling).

## Scope

### Changes (interactive path only)

- Add `github.com/charmbracelet/huh` to `go.mod`. Transitive: bubbletea,
  lipgloss, etc. Runtime is unaffected — the binary stays committed; only
  `build.sh` downloads modules at build time (Go already required to build).
- New `form.go` with `huh`-based helpers. Delete `prompt.go` (its `askMenu`,
  `askText`, `askTextNoPipe`, `confirm`, `readLine`, and the `prompt*` loops
  are replaced).
- Rewrite `run()`, `runFlat()`, `runHyper()` in `main.go` to assemble forms.

### Untouched

`cli.go` (flag mode), `validateKey`, `validateGokuCombo`, `sectionKeys`,
`hyperModsForKey`, `buildFlatLine`, `upsertFlatEntry`, `upsertHyperEntry`,
`build`, `deploy`, `reportFlat`, `readPool`/`comboForKey`, and all existing
`*_test.go` files.

## Form flow

### Flat layers (app / workspace / l1 / l2 / l3)

1. `huh.Select` — **layer** (`layerOrder`).
2. workspace only: `huh.Select` — base (opt+key) vs shift (opt+shift+key) →
   selects `workspace` vs `workspace-shift` section.
3. Detail form (one form, conditional fields via `WithHideFunc`):
   - `huh.Input` **Key** — Description lists free keys for the section
     (`free: a b d g …`); `Validate` runs `validateKey(key, allowUpper)` for
     format only and **allows** collisions.
   - `huh.Input` **Label** — `Validate` rejects `|`.
   - **Target** — `huh.Select` for type, plus a conditional `huh.Input`:
     - app: `App (open -a)` → app-name input | `Raw goku combo (!…)` →
       combo input (`validateGokuCombo`).
     - workspace: single aerospace-command input (no select).
     - l1/l2/l3: `F-key pool` (→ blank extra) | `open:App` → app-name input |
       `Raw goku combo` → combo input (`validateGokuCombo`).
4. If the key collides with an existing mapping → `huh.Confirm`
   "`X` already maps `Y` — overwrite?" (a No cancels).
5. Build preview line (`buildFlatLine`), `huh.Confirm` "Proceed?" → write →
   `build` → `reportFlat` → `huh.Confirm` "Deploy now (chezmoi apply && goku)?"
   → `deploy` or print manual instructions.

### Hyper layer (hyperkeys.yaml)

1. `huh.Input` **Key** (suggestions + `validateKey(key, false)`).
2. `huh.Select` **Modifier slot** (`hyperModSlots`); if the slot is already
   taken for that key, a `huh.Confirm` overwrite gate.
3. `huh.Input` **Action** (goku key code / comma sequence);
   `validateGokuCombo` when it starts with `!` or `#`.
4. `huh.Input` **Label**.
5. Preview + `huh.Confirm` "Proceed?" → write → `build` →
   success report → deploy confirm.

## TTY guard

`huh.Run()` requires a terminal. Detect non-TTY stdin (e.g.
`term.IsTerminal(int(os.Stdin.Fd()))`) at the start of `run()` and exit with:
`add-keymap: not a terminal — for unattended use run with flags (see -h)`.
This replaces today's EOF-abort logic in `readLine`.

## Testing

Existing `*_test.go` (validation, YAML edits, pool, CLI parsing) stay green and
untouched — they cover the pure logic. The new form code is thin glue over
already-tested functions; `huh` forms can't be unit-tested without a pty, so no
new TUI tests. Verification is manual: build via `build.sh`, run the wizard for
a flat layer and the hyper layer, confirm the YAML/edit/build/deploy path
matches the old behavior.

## Out of scope

- Custom theming (tokyonight palette).
- Changes to flag/CLI mode.
- New tests for TUI rendering.
