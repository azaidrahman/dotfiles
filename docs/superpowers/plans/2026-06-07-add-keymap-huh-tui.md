# add-keymap huh TUI Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `add-keymap` wizard's hand-rolled `bufio` prompts with `charmbracelet/huh` forms (arrow-key selects, inline validation, live free-key hints), leaving the flag mode and YAML logic untouched.

**Architecture:** Sequential `huh` forms. A new `form.go` holds the form-runner helper, a TTY guard, and a deterministic free-key hint builder. `run()`/`runFlat()`/`runHyper()` are rewritten to assemble forms from the existing (already-tested) validation and YAML-edit functions. `prompt.go` is deleted.

**Tech Stack:** Go 1.26, `github.com/charmbracelet/huh`.

---

## Working directory

All Go source lives in the chezmoi **source** tree (edit here, not the deployed copy):

```
/Users/zaid/.local/share/chezmoi/dot_config/private_karabiner/src/add-keymap
```

Refer to it as `$SRC` below. The committed binary is built to `../../scripts/executable_add-keymap` by `build.sh`.

## File structure

- `$SRC/go.mod`, `$SRC/go.sum` — **modify**: add `huh` dependency.
- `$SRC/form.go` — **create**: `runForm`, `ensureTTY`, `freeKeyHint`.
- `$SRC/form_test.go` — **create**: tests for `freeKeyHint`.
- `$SRC/main.go` — **modify**: rewrite `run`, `runFlat`, `runHyper`.
- `$SRC/prompt.go` — **delete**: its helpers are replaced by `form.go` + inline forms.
- Untouched: `cli.go`, `keys.go`, `layers.go`, `pool.go`, `yamledit.go`, `deploy.go`, and all existing `*_test.go`.

## Pre-flight

The validation/data primitives this plan reuses already exist:
`validateKey(key, allowUpper)`, `validateGokuCombo(s)`, `sectionKeys(text, section)`,
`hyperModsForKey(text, key)`, `buildFlatLine`, `upsertFlatEntry`, `upsertHyperEntry`,
`build`, `deploy`, `reportFlat`, `readPool`/`comboForKey`, `hyperAction`,
`resolveSourceDir`, `layerByID`, `layerOrder`, `hyperModSlots`,
`qwertyLetters`, `digits`, `specialNames`.

---

### Task 1: Add huh dependency

**Files:**
- Modify: `$SRC/go.mod`, `$SRC/go.sum`

- [ ] **Step 1: Add the module**

Run (needs network):
```bash
cd /Users/zaid/.local/share/chezmoi/dot_config/private_karabiner/src/add-keymap
go get github.com/charmbracelet/huh@latest
go mod tidy
```
Expected: `go.mod` gains a `require github.com/charmbracelet/huh vX.Y.Z` line; `go.sum` populated.

- [ ] **Step 2: Verify it compiles and existing tests still pass**

Run: `go test ./...`
Expected: PASS (no code uses huh yet; just confirms the module graph is sound).

- [ ] **Step 3: Commit**

```bash
git -C /Users/zaid/.local/share/chezmoi add dot_config/private_karabiner/src/add-keymap/go.mod dot_config/private_karabiner/src/add-keymap/go.sum
git -C /Users/zaid/.local/share/chezmoi commit -m "build(karabiner): add charmbracelet/huh dependency"
```

---

### Task 2: form.go helpers (TDD the free-key hint)

**Files:**
- Create: `$SRC/form.go`
- Test: `$SRC/form_test.go`

`freeKeyHint` lists the candidate keys not already mapped, in a **deterministic** order (letters, digits, then a fixed symbol list) so it is testable. `ensureTTY` replaces the old EOF-abort. `runForm` runs a form and converts a user abort (Esc/Ctrl-C) into the wizard's existing `"cancelled"` error.

- [ ] **Step 1: Write the failing test**

Create `$SRC/form_test.go`:
```go
package main

import "testing"

func TestFreeKeyHint(t *testing.T) {
	existing := map[string]bool{"a": true, "b": true, "-": true}
	got := freeKeyHint(existing)
	want := "free: c d e f g h i j k l m n o p q r s t u v w x y z " +
		"0 1 2 3 4 5 6 7 8 9 = [ ] ; ' , . / \\ ` space"
	if got != want {
		t.Fatalf("freeKeyHint mismatch:\n got: %q\nwant: %q", got, want)
	}
}

func TestFreeKeyHintNoneFree(t *testing.T) {
	existing := map[string]bool{}
	for _, r := range qwertyLetters {
		existing[string(r)] = true
	}
	for _, r := range digits {
		existing[string(r)] = true
	}
	for _, s := range symbolKeys {
		existing[s] = true
	}
	if got := freeKeyHint(existing); got != "free: (none — all keys taken)" {
		t.Fatalf("expected none-free sentinel, got %q", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./... -run TestFreeKeyHint -v`
Expected: FAIL — `undefined: freeKeyHint` / `undefined: symbolKeys`.

- [ ] **Step 3: Write form.go**

Create `$SRC/form.go`:
```go
package main

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/huh"
)

// symbolKeys is the fixed-order set of non-alphanumeric keys offered as
// candidates (matches the symbol forms accepted by validateKey). Kept as an
// ordered slice so freeKeyHint is deterministic (specialNames is a map).
var symbolKeys = []string{
	"=", "[", "]", ";", "'", ",", ".", "/", "\\", "`", "-", "space",
}

// freeKeyHint returns a "free: ..." line listing candidate keys not present in
// existing, in a stable order (letters, digits, symbols). Shown in the key
// field's Description so the user can see what's open while typing.
func freeKeyHint(existing map[string]bool) string {
	var free []string
	add := func(k string) {
		if !existing[k] {
			free = append(free, k)
		}
	}
	for _, r := range qwertyLetters {
		add(string(r))
	}
	for _, r := range digits {
		add(string(r))
	}
	// Symbols in a fixed order; "-" placed after digits/before space to match tests.
	for _, s := range []string{"=", "[", "]", ";", "'", ",", ".", "/", "\\", "`", "-", "space"} {
		add(s)
	}
	if len(free) == 0 {
		return "free: (none — all keys taken)"
	}
	return "free: " + strings.Join(free, " ")
}

// ensureTTY aborts early when stdin is not an interactive terminal, since huh
// forms require one. Replaces the old EOF-abort in readLine.
func ensureTTY() error {
	fi, err := os.Stdin.Stat()
	if err != nil || fi.Mode()&os.ModeCharDevice == 0 {
		return fmt.Errorf("not a terminal — for unattended use run with flags (see -h)")
	}
	return nil
}

// runForm runs a huh form, mapping a user abort (Esc / Ctrl-C) to the wizard's
// existing "cancelled" error so callers handle it uniformly.
func runForm(groups ...*huh.Group) error {
	err := huh.NewForm(groups...).Run()
	if errors.Is(err, huh.ErrUserAborted) {
		return fmt.Errorf("cancelled")
	}
	return err
}
```

Note: `symbolKeys` is declared for the test's none-free case; the ordered list
is repeated inline in `freeKeyHint` rather than ranged over `symbolKeys`
because the hint order ("-" late) differs from nothing else — keep both in sync.
(If you prefer, range `symbolKeys` directly and reorder it to match the test's
expected string; either is fine as long as the test passes.)

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./... -run TestFreeKeyHint -v`
Expected: PASS (both subtests).

- [ ] **Step 5: Run the full suite**

Run: `go test ./...`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git -C /Users/zaid/.local/share/chezmoi add dot_config/private_karabiner/src/add-keymap/form.go dot_config/private_karabiner/src/add-keymap/form_test.go
git -C /Users/zaid/.local/share/chezmoi commit -m "feat(karabiner): add huh form helpers + free-key hint"
```

---

### Task 3: Rewrite the flat-layer flow with huh

**Files:**
- Modify: `$SRC/main.go` (`run`, `runFlat`, and the `promptKey`/`promptAppTarget`/`promptShortcutTarget` helpers move into `runFlat`)

Replaces numbered menus with `huh.Select` and line prompts with validated
`huh.Input`. The key field allows collisions (format-only validate) and shows
the free-key hint; a colliding key triggers an overwrite `huh.Confirm`.

- [ ] **Step 1: Rewrite `run` and `runFlat`**

In `$SRC/main.go`, replace the `run()`, `runFlat()`, `promptKey()`,
`promptAppTarget()`, and `promptShortcutTarget()` functions with:

```go
func run() error {
	if err := ensureTTY(); err != nil {
		return err
	}
	srcDir, err := resolveSourceDir()
	if err != nil {
		return err
	}
	fmt.Println("add-keymap — karabiner source:", srcDir)

	layerID := layerOrder[0]
	if err := runForm(huh.NewGroup(
		huh.NewSelect[string]().
			Title("Which layer?").
			Options(huh.NewOptions(layerOrder...)...).
			Value(&layerID),
	)); err != nil {
		return err
	}
	layer := layerByID[layerID]

	if layerID == "hyper" {
		return runHyper(srcDir, layer)
	}
	return runFlat(srcDir, layer)
}

// runFlat handles app / workspace / l1 / l2 / l3.
func runFlat(srcDir string, layer Layer) error {
	path := filepath.Join(srcDir, layer.File)
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(b)

	// Workspace: choose base vs shift section.
	section := layer.Section
	if layer.ID == "workspace" {
		variant := "base"
		if err := runForm(huh.NewGroup(
			huh.NewSelect[string]().
				Title("Base or shift variant?").
				Options(
					huh.NewOption("base (opt+key)", "base"),
					huh.NewOption("shift (opt+shift+key)", "shift"),
				).
				Value(&variant),
		)); err != nil {
			return err
		}
		if variant == "shift" {
			section = "workspace-shift"
		}
	}

	existing := sectionKeys(text, section)

	// Key + label in one form. Key allows collisions (validated for format only);
	// the free-key hint is shown in the description.
	var key, label string
	if err := runForm(huh.NewGroup(
		huh.NewInput().
			Title("Key to map").
			Description(freeKeyHint(existing)).
			Validate(func(s string) error { return validateKey(strings.TrimSpace(s), layer.AllowUpper) }).
			Value(&key),
		huh.NewInput().
			Title("Label (short, shown in help overlay)").
			Validate(noPipe).
			Value(&label),
	)); err != nil {
		return err
	}
	key = strings.TrimSpace(key)
	label = strings.TrimSpace(label)

	// Collision → overwrite confirm.
	if existing[key] {
		ok := false
		if err := runForm(huh.NewGroup(
			huh.NewConfirm().
				Title(fmt.Sprintf("%q is already mapped in this layer — overwrite?", key)).
				Value(&ok),
		)); err != nil {
			return err
		}
		if !ok {
			return fmt.Errorf("cancelled")
		}
	}

	extra, err := promptFlatTarget(layer)
	if err != nil {
		return err
	}

	line := buildFlatLine(key, label, extra)
	fmt.Printf("\nWill add to %s [%s]:\n  %s\n", layer.File, section, line)
	proceed := false
	if err := runForm(huh.NewGroup(
		huh.NewConfirm().Title("Proceed?").Value(&proceed),
	)); err != nil {
		return err
	}
	if !proceed {
		return fmt.Errorf("cancelled")
	}

	updated, err := upsertFlatEntry(text, section, key, line)
	if err != nil {
		return err
	}
	if err := os.WriteFile(path, []byte(updated), 0o644); err != nil {
		return err
	}
	if err := build(srcDir); err != nil {
		return err
	}
	reportFlat(srcDir, layer, section, key, extra)
	return maybeDeploy(srcDir)
}

// promptFlatTarget collects the YAML "extra" field per layer type.
func promptFlatTarget(layer Layer) (string, error) {
	switch layer.ID {
	case "workspace":
		var cmd string
		if err := runForm(huh.NewGroup(
			huh.NewInput().
				Title("Aerospace command (e.g. 'workspace 1')").
				Validate(noPipe).
				Value(&cmd),
		)); err != nil {
			return "", err
		}
		return strings.TrimSpace(cmd), nil

	case "app":
		kind := "app"
		if err := runForm(huh.NewGroup(
			huh.NewSelect[string]().
				Title("Target type").
				Options(
					huh.NewOption("App (open -a)", "app"),
					huh.NewOption("Raw goku combo (!…)", "combo"),
				).
				Value(&kind),
		)); err != nil {
			return "", err
		}
		if kind == "combo" {
			return promptCombo("Goku combo (e.g. !Cgrave_accent_and_tilde)")
		}
		var app string
		if err := runForm(huh.NewGroup(
			huh.NewInput().
				Title("App name (as in /Applications, e.g. 'Microsoft Teams')").
				Validate(noPipe).
				Value(&app),
		)); err != nil {
			return "", err
		}
		return strings.TrimSpace(app), nil

	default: // l1, l2, l3
		kind := "pool"
		if err := runForm(huh.NewGroup(
			huh.NewSelect[string]().
				Title("Mapping type").
				Options(
					huh.NewOption("F-key pool (auto-assign a combo to bind in Alfred/KM)", "pool"),
					huh.NewOption("Direct: open an app (open:App)", "open"),
					huh.NewOption("Direct: raw goku combo (!…)", "combo"),
				).
				Value(&kind),
		)); err != nil {
			return "", err
		}
		switch kind {
		case "pool":
			return "", nil
		case "open":
			var app string
			if err := runForm(huh.NewGroup(
				huh.NewInput().Title("App name").Validate(noPipe).Value(&app),
			)); err != nil {
				return "", err
			}
			return "open:" + strings.TrimSpace(app), nil
		default:
			return promptCombo("Goku combo (e.g. !CSf13)")
		}
	}
}

// promptCombo asks for a goku combo and validates it.
func promptCombo(title string) (string, error) {
	var c string
	if err := runForm(huh.NewGroup(
		huh.NewInput().
			Title(title).
			Validate(func(s string) error { return validateGokuCombo(strings.TrimSpace(s)) }).
			Value(&c),
	)); err != nil {
		return "", err
	}
	return strings.TrimSpace(c), nil
}

// noPipe rejects values containing '|' (the YAML field delimiter).
func noPipe(s string) error {
	if strings.TrimSpace(s) == "" {
		return fmt.Errorf("value cannot be empty")
	}
	if strings.Contains(s, "|") {
		return fmt.Errorf("value cannot contain '|'")
	}
	return nil
}
```

- [ ] **Step 2: Add the huh import to main.go**

Ensure `$SRC/main.go`'s import block includes `"github.com/charmbracelet/huh"` (and still has `"os"`, `"fmt"`, `"path/filepath"`, `"strings"`). Remove `parseCLI` is untouched.

- [ ] **Step 3: Build (compile check — will fail to link until Task 4 removes prompt.go references)**

Run: `go build ./...`
Expected: it may still compile because `prompt.go` (`askMenu` etc.) and `runHyper`'s old body remain. If you get "declared and not used" or duplicate-symbol errors, that's expected to resolve in Task 4 — proceed only if the error is confined to `prompt.go`/`runHyper` usage. If `runFlat` itself has errors, fix them now.

- [ ] **Step 4: Commit**

```bash
git -C /Users/zaid/.local/share/chezmoi add dot_config/private_karabiner/src/add-keymap/main.go
git -C /Users/zaid/.local/share/chezmoi commit -m "feat(karabiner): huh forms for flat-layer add-keymap flow"
```

---

### Task 4: Rewrite the hyper flow and delete prompt.go

**Files:**
- Modify: `$SRC/main.go` (`runHyper`)
- Delete: `$SRC/prompt.go`

- [ ] **Step 1: Rewrite `runHyper`**

In `$SRC/main.go`, replace `runHyper`, `promptHyperKey`, and `maybeDeploy` with:

```go
// runHyper handles the nested hyperkeys.yaml.
func runHyper(srcDir string, layer Layer) error {
	path := filepath.Join(srcDir, layer.File)
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(b)

	var key string
	if err := runForm(huh.NewGroup(
		huh.NewInput().
			Title("Key to map (under CapsLock/hyper)").
			Validate(func(s string) error { return validateKey(strings.TrimSpace(s), false) }).
			Value(&key),
	)); err != nil {
		return err
	}
	key = strings.TrimSpace(key)
	existing := hyperModsForKey(text, key)

	mod := hyperModSlots[0]
	if err := runForm(huh.NewGroup(
		huh.NewSelect[string]().
			Title("Modifier slot").
			Options(huh.NewOptions(hyperModSlots...)...).
			Value(&mod),
	)); err != nil {
		return err
	}
	if existing[mod] {
		ok := false
		if err := runForm(huh.NewGroup(
			huh.NewConfirm().
				Title(fmt.Sprintf("hyper+%s already maps %q — overwrite?", key, mod)).
				Value(&ok),
		)); err != nil {
			return err
		}
		if !ok {
			return fmt.Errorf("cancelled")
		}
	}

	var rawAction, label string
	if err := runForm(huh.NewGroup(
		huh.NewInput().
			Title("Action (goku key code, or comma-separated sequence)").
			Validate(func(s string) error {
				s = strings.TrimSpace(s)
				if s == "" {
					return fmt.Errorf("action cannot be empty")
				}
				if strings.HasPrefix(s, "!") || strings.HasPrefix(s, "#") {
					return validateGokuCombo(s)
				}
				return nil
			}).
			Value(&rawAction),
		huh.NewInput().
			Title("Label (help overlay)").
			Validate(noPipe).
			Value(&label),
	)); err != nil {
		return err
	}
	rawAction = strings.TrimSpace(rawAction)
	label = strings.TrimSpace(label)
	action := hyperAction(rawAction)

	fmt.Printf("\nWill add under hyper.%s:\n    %s: %s # %s\n", key, mod, action, label)
	proceed := false
	if err := runForm(huh.NewGroup(
		huh.NewConfirm().Title("Proceed?").Value(&proceed),
	)); err != nil {
		return err
	}
	if !proceed {
		return fmt.Errorf("cancelled")
	}

	updated, err := upsertHyperEntry(text, key, mod, action, label)
	if err != nil {
		return err
	}
	if err := os.WriteFile(path, []byte(updated), 0o644); err != nil {
		return err
	}
	if err := build(srcDir); err != nil {
		return err
	}
	fmt.Printf("\n✓ Mapped: CapsLock + %s + %s → %s (%s)\n", mod, key, action, label)
	return maybeDeploy(srcDir)
}

// maybeDeploy offers to chezmoi apply + goku.
func maybeDeploy(srcDir string) error {
	deployNow := false
	if err := runForm(huh.NewGroup(
		huh.NewConfirm().Title("Deploy now (chezmoi apply && goku)?").Value(&deployNow),
	)); err != nil {
		return err
	}
	if deployNow {
		return deploy(srcDir)
	}
	fmt.Println("\nSkipped. To deploy later:\n  chezmoi apply && goku")
	return nil
}
```

- [ ] **Step 2: Delete prompt.go**

Run: `rm /Users/zaid/.local/share/chezmoi/dot_config/private_karabiner/src/add-keymap/prompt.go`

- [ ] **Step 3: Build**

Run:
```bash
cd /Users/zaid/.local/share/chezmoi/dot_config/private_karabiner/src/add-keymap
go build ./...
```
Expected: clean build, no undefined-symbol errors (all `askMenu`/`askText`/`confirm` callers are gone).

- [ ] **Step 4: Run the full test suite**

Run: `go test ./...`
Expected: PASS — existing logic tests plus `TestFreeKeyHint`.

- [ ] **Step 5: Commit**

```bash
git -C /Users/zaid/.local/share/chezmoi add -A dot_config/private_karabiner/src/add-keymap/
git -C /Users/zaid/.local/share/chezmoi commit -m "feat(karabiner): huh forms for hyper flow; drop bufio prompt.go"
```

---

### Task 5: Rebuild binary, verify wizard, deploy

**Files:**
- Modify: `$SRC/../../scripts/executable_add-keymap` (rebuilt binary)

- [ ] **Step 1: Rebuild the committed binary**

Run:
```bash
cd /Users/zaid/.local/share/chezmoi/dot_config/private_karabiner/src/add-keymap
./build.sh
```
Expected: `Built scripts/executable_add-keymap`.

- [ ] **Step 2: Non-TTY guard check**

Run: `printf '' | ./../../scripts/executable_add-keymap` (no flags, piped empty stdin)
Expected: exits non-zero printing `not a terminal — for unattended use run with flags (see -h)`.

- [ ] **Step 3: Flag mode still works (regression)**

Run (dry, no deploy) against a scratch copy or with `-overwrite` on a throwaway key, e.g.:
```bash
./../../scripts/executable_add-keymap -h
```
Expected: usage text prints (confirms `cli.go` path untouched and binary runs).

- [ ] **Step 4: Manual interactive verification**

In an interactive terminal, run `~/.config/karabiner/scripts/add-keymap` (after Step 6 applies it) OR run the freshly built `./../../scripts/executable_add-keymap` directly. Verify:
- Layer select navigates with arrow keys.
- Key field shows `free: …` hint and rejects an invalid key inline.
- Choosing an already-mapped key prompts the overwrite confirm.
- An l-layer "F-key pool" choice writes a blank extra; "Raw goku combo" validates the combo inline.
- Hyper flow: key → mod slot → action (combo validated) → label → preview → deploy confirm.
- Declining the final confirm prints the manual deploy hint and writes nothing.

Use a throwaway key you then revert (`git -C /Users/zaid/.local/share/chezmoi checkout dot_config/private_karabiner/config/`) so verification doesn't leave stray mappings.

- [ ] **Step 5: Commit the rebuilt binary**

```bash
git -C /Users/zaid/.local/share/chezmoi add dot_config/private_karabiner/scripts/executable_add-keymap
git -C /Users/zaid/.local/share/chezmoi commit -m "build(karabiner): rebuild add-keymap binary with huh TUI"
```

- [ ] **Step 6: Deploy**

Run: `chezmoi apply ~/.config/karabiner`
Expected: `Done!` — the new binary lands at `~/.config/karabiner/scripts/add-keymap`. (No edn changed, so goku need not re-run; if `run_onchange_goku.sh` fires it's harmless.)

---

## Notes / deviations from the spec

- The spec described conditional target fields via `WithHideFunc` in one form.
  This plan uses **sequential forms** for the target branch instead (a type
  `Select`, then a follow-up `Input`). Reason: hidden-field validation in huh is
  subtle, and sequential forms keep each step's validation unambiguous. Net UX
  is the same arrow-key + inline-validation experience.
- No new TUI tests (huh needs a pty). `freeKeyHint` is the one new pure function
  and is unit-tested; everything else is glue over already-tested helpers and is
  covered by the manual verification in Task 5.
