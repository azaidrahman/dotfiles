# add-keymap Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an interactive Go CLI (`add-keymap`) that walks the user through adding a keymap to any layer (app / workspace / l1-l3 / hyper), validates the key, writes the YAML, builds, and reports the resulting mapping.

**Architecture:** A single-package Go program in `src/add-keymap/`, compiled to a committed binary `scripts/executable_add-keymap`. It edits the chezmoi *source* YAML configs (resolved via `chezmoi source-path`), then shells out to the existing `./build.sh` (the Python generator remains the single source of truth for EDN generation and F-key pool allocation), then reads back `data/fkey-pool.json` to report the assigned combo. Only the slot→combo *render* table is mirrored from `lib/pool.py`.

**Tech Stack:** Go 1.26 (stdlib only — `bufio`, `os/exec`, `encoding/json`, `strings`), no external deps. Existing Python generator + goku + chezmoi for deploy.

---

## File Structure

All paths relative to repo root `dot_config/private_karabiner/`.

- `src/add-keymap/go.mod` — module definition, `package main`.
- `src/add-keymap/pool.go` — `FKEY_POOL`/`ALL_MODS` render table, `slotToCombo`, `readPool`, `comboForKey`.
- `src/add-keymap/pool_test.go`
- `src/add-keymap/keys.go` — allowed-key set, special-name map, `validateKey`.
- `src/add-keymap/keys_test.go`
- `src/add-keymap/yamledit.go` — line-based read/collision/append/overwrite for flat sections + hyper nested edits.
- `src/add-keymap/yamledit_test.go`
- `src/add-keymap/layers.go` — layer metadata + pure functions that build the YAML line/block for each layer from user inputs.
- `src/add-keymap/layers_test.go`
- `src/add-keymap/prompt.go` — stdin prompt helpers (menu, text, confirm).
- `src/add-keymap/deploy.go` — source-dir resolution + run `build.sh`/`chezmoi apply`/`goku`.
- `src/add-keymap/main.go` — wires the interactive flow.
- `src/add-keymap/build.sh` — `go build` → `scripts/executable_add-keymap`.
- `scripts/executable_add-keymap` — committed compiled binary (built in final task).
- `README.md` — add a usage section (final task).

---

## Task 1: Scaffold the Go module

**Files:**
- Create: `src/add-keymap/go.mod`
- Create: `src/add-keymap/main.go`
- Create: `src/add-keymap/build.sh`

- [ ] **Step 1: Create the module file**

`src/add-keymap/go.mod`:
```
module add-keymap

go 1.26
```

- [ ] **Step 2: Create a minimal main.go**

`src/add-keymap/main.go`:
```go
package main

import "fmt"

func main() {
	fmt.Println("add-keymap")
}
```

- [ ] **Step 3: Create the build script**

`src/add-keymap/build.sh`:
```bash
#!/bin/bash
# Compile the add-keymap wizard into the committed binary.
# Run this after changing any Go source here.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
go build -o ../../scripts/executable_add-keymap .
echo "Built scripts/executable_add-keymap"
```

- [ ] **Step 4: Verify it compiles and runs**

Run: `cd src/add-keymap && go run . && chmod +x build.sh`
Expected: prints `add-keymap`, no errors.

- [ ] **Step 5: Commit**

```bash
git add src/add-keymap/go.mod src/add-keymap/main.go src/add-keymap/build.sh
git commit -m "feat(karabiner): scaffold add-keymap Go module"
```

---

## Task 2: F-key pool render table + reader

**Files:**
- Create: `src/add-keymap/pool.go`
- Test: `src/add-keymap/pool_test.go`

- [ ] **Step 1: Write the failing test**

`src/add-keymap/pool_test.go`:
```go
package main

import "testing"

func TestSlotToCombo(t *testing.T) {
	cases := map[int]string{
		0:  "F13",          // fkey 0, mod ""
		2:  "cmd+F13",      // fkey 0, mod "cmd+"
		3:  "opt+F13",      // fkey 0, mod "opt+"
		10: "cmd+shift+F13", // fkey 0, mod 10
		16: "F14",          // fkey 1, mod ""
	}
	for slot, want := range cases {
		if got := slotToCombo(slot); got != want {
			t.Errorf("slotToCombo(%d) = %q, want %q", slot, got, want)
		}
	}
}

func TestComboForKey(t *testing.T) {
	pool := map[string]int{"l1:o": 0, "l1:c": 10}
	got, ok := comboForKey(pool, "l1", "o")
	if !ok || got != "F13" {
		t.Errorf("comboForKey l1:o = %q,%v want F13,true", got, ok)
	}
	if _, ok := comboForKey(pool, "l1", "z"); ok {
		t.Errorf("comboForKey l1:z should be missing")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src/add-keymap && go test ./... -run 'TestSlotToCombo|TestComboForKey'`
Expected: FAIL — `undefined: slotToCombo` / `comboForKey`.

- [ ] **Step 3: Write the implementation**

`src/add-keymap/pool.go`:
```go
package main

import (
	"encoding/json"
	"os"
	"strings"
)

// Mirrors FKEY_POOL and ALL_MODS in lib/pool.py. Pool *allocation* stays in
// Python (generate.py); this table only renders an already-assigned slot for
// display. Keep in sync with lib/pool.py if that table changes.
var fkeyPool = []string{"f13", "f14", "f16", "f17", "f18", "f19", "f20"}

var allMods = []struct{ human, goku string }{
	{"", ""},
	{"ctrl+", "!T"},
	{"cmd+", "!C"},
	{"opt+", "!O"},
	{"ctrl+cmd+", "!CT"},
	{"ctrl+opt+", "!TO"},
	{"cmd+opt+", "!CO"},
	{"ctrl+cmd+opt+", "!CTO"},
	{"shift+", "!S"},
	{"ctrl+shift+", "!TS"},
	{"cmd+shift+", "!CS"},
	{"opt+shift+", "!OS"},
	{"ctrl+cmd+shift+", "!CTS"},
	{"ctrl+opt+shift+", "!TOS"},
	{"cmd+opt+shift+", "!COS"},
	{"ctrl+cmd+opt+shift+", "!CTOS"},
}

// slotToCombo renders a pool slot index as a human combo like "cmd+F16".
func slotToCombo(slot int) string {
	fkey := fkeyPool[slot/len(allMods)]
	mod := allMods[slot%len(allMods)]
	return mod.human + strings.ToUpper(fkey)
}

// readPool loads data/fkey-pool.json as a layer:key -> slot map.
// Missing file yields an empty map (not an error).
func readPool(path string) (map[string]int, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return map[string]int{}, nil
	}
	if err != nil {
		return nil, err
	}
	m := map[string]int{}
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, err
	}
	return m, nil
}

// comboForKey returns the rendered combo for a (layer,key) if assigned.
func comboForKey(pool map[string]int, layer, key string) (string, bool) {
	slot, ok := pool[layer+":"+key]
	if !ok {
		return "", false
	}
	return slotToCombo(slot), true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src/add-keymap && go test ./... -run 'TestSlotToCombo|TestComboForKey'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/add-keymap/pool.go src/add-keymap/pool_test.go
git commit -m "feat(karabiner): add-keymap pool slot->combo render + reader"
```

---

## Task 3: Key validation + special names

**Files:**
- Create: `src/add-keymap/keys.go`
- Test: `src/add-keymap/keys_test.go`

- [ ] **Step 1: Write the failing test**

`src/add-keymap/keys_test.go`:
```go
package main

import "testing"

func TestValidateKey(t *testing.T) {
	valid := []struct {
		key        string
		allowUpper bool
	}{
		{"a", false}, {"z", false}, {"5", false},
		{"-", false}, {"space", false}, {"slash", false},
		{"W", true}, {"G", true},
	}
	for _, c := range valid {
		if err := validateKey(c.key, c.allowUpper); err != nil {
			t.Errorf("validateKey(%q,%v) unexpected error: %v", c.key, c.allowUpper, err)
		}
	}
	invalid := []struct {
		key        string
		allowUpper bool
	}{
		{"", false},        // empty
		{"ab", false},      // multi-char non-special
		{"W", false},       // uppercase not allowed in this layer
		{"§", false},       // not in set
		{"ctrl", false},    // not a key name
	}
	for _, c := range invalid {
		if err := validateKey(c.key, c.allowUpper); err == nil {
			t.Errorf("validateKey(%q,%v) expected error, got nil", c.key, c.allowUpper)
		}
	}
}

func TestGokuName(t *testing.T) {
	if gokuName("-") != "hyphen" {
		t.Errorf("gokuName(-) = %q want hyphen", gokuName("-"))
	}
	if gokuName("a") != "a" {
		t.Errorf("gokuName(a) = %q want a", gokuName("a"))
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src/add-keymap && go test ./... -run 'TestValidateKey|TestGokuName'`
Expected: FAIL — `undefined: validateKey` / `gokuName`.

- [ ] **Step 3: Write the implementation**

`src/add-keymap/keys.go`:
```go
package main

import (
	"fmt"
	"strings"
)

// specialNames maps a literal symbol (as typed in YAML) to its goku key name.
// Mirrors GOKU_NAMES in lib/parser.py.
var specialNames = map[string]string{
	"-": "hyphen", "=": "equal_sign", "[": "open_bracket", "]": "close_bracket",
	";": "semicolon", "'": "quote", ",": "comma", ".": "period",
	"/": "slash", "\\": "backslash", "`": "grave_accent_and_tilde",
	"space": "spacebar",
}

// longNames is the set of accepted multi-char key tokens (e.g. "space", "hyphen").
// Accept both the symbol form ("-") and the long form ("hyphen").
var longNames = func() map[string]bool {
	m := map[string]bool{}
	for sym, long := range specialNames {
		m[sym] = true
		m[long] = true
	}
	return m
}()

const qwertyLetters = "abcdefghijklmnopqrstuvwxyz"
const digits = "0123456789"

// gokuName returns the goku key name for a YAML key token (symbol or already long).
func gokuName(key string) string {
	if long, ok := specialNames[key]; ok {
		return long
	}
	return key
}

// validateKey checks a key token is a usable single key.
// allowUpper permits an uppercase letter (the shift variant, used by app/workspace).
func validateKey(key string, allowUpper bool) error {
	if key == "" {
		return fmt.Errorf("key is empty")
	}
	if longNames[key] {
		return nil
	}
	if len(key) == 1 {
		r := key[0]
		if strings.IndexByte(qwertyLetters, r|0x20) >= 0 {
			if r >= 'A' && r <= 'Z' && !allowUpper {
				return fmt.Errorf("uppercase key %q not allowed in this layer", key)
			}
			return nil
		}
		if strings.IndexByte(digits, r) >= 0 {
			return nil
		}
	}
	return fmt.Errorf("invalid key %q (use a letter, digit, or one of: - = [ ] ; ' , . / \\ ` space)", key)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src/add-keymap && go test ./... -run 'TestValidateKey|TestGokuName'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/add-keymap/keys.go src/add-keymap/keys_test.go
git commit -m "feat(karabiner): add-keymap key validation + special names"
```

---

## Task 4: Flat-section read + collision scan

**Files:**
- Create: `src/add-keymap/yamledit.go`
- Test: `src/add-keymap/yamledit_test.go`

- [ ] **Step 1: Write the failing test**

`src/add-keymap/yamledit_test.go`:
```go
package main

import "testing"

const sampleFlat = `app:
  # key | label | app
  - w | WA | Whatsapp
  - W | messages | Messages
  - e | obsidian | Obsidian

other:
  - x | foo | Bar
`

func TestSectionKeys(t *testing.T) {
	keys := sectionKeys(sampleFlat, "app")
	for _, k := range []string{"w", "W", "e"} {
		if !keys[k] {
			t.Errorf("expected key %q present in app section", k)
		}
	}
	if keys["x"] {
		t.Errorf("key x from 'other' leaked into app section")
	}
	if len(keys) != 3 {
		t.Errorf("got %d keys, want 3: %v", len(keys), keys)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src/add-keymap && go test ./... -run TestSectionKeys`
Expected: FAIL — `undefined: sectionKeys`.

- [ ] **Step 3: Write the implementation**

`src/add-keymap/yamledit.go`:
```go
package main

import (
	"regexp"
	"strings"
)

var sectionHeaderRe = regexp.MustCompile(`^[a-z][\w-]*:\s*$`)

// firstField returns the trimmed key (first |-field) of a "- key | ..." item.
func firstField(itemBody string) string {
	parts := strings.SplitN(itemBody, "|", 2)
	return strings.TrimSpace(parts[0])
}

// sectionKeys returns the set of keys present in a flat section of YAML text.
func sectionKeys(text, section string) map[string]bool {
	keys := map[string]bool{}
	inSection := false
	for _, line := range strings.Split(text, "\n") {
		stripped := strings.TrimSpace(line)
		if sectionHeaderRe.MatchString(stripped) {
			inSection = strings.TrimSuffix(stripped, ":") == section
			continue
		}
		if !inSection || stripped == "" || strings.HasPrefix(stripped, "#") {
			continue
		}
		if strings.HasPrefix(stripped, "- ") {
			keys[firstField(stripped[2:])] = true
		}
	}
	return keys
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src/add-keymap && go test ./... -run TestSectionKeys`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/add-keymap/yamledit.go src/add-keymap/yamledit_test.go
git commit -m "feat(karabiner): add-keymap flat-section key scan"
```

---

## Task 5: Append + overwrite in flat sections (comment-preserving)

**Files:**
- Modify: `src/add-keymap/yamledit.go`
- Modify: `src/add-keymap/yamledit_test.go`

- [ ] **Step 1: Write the failing test**

Append to `src/add-keymap/yamledit_test.go`:
```go
func TestAppendFlatEntry(t *testing.T) {
	got, err := upsertFlatEntry(sampleFlat, "app", "g", "- g | iPhone | iPhone Mirroring")
	if err != nil {
		t.Fatal(err)
	}
	want := `app:
  # key | label | app
  - w | WA | Whatsapp
  - W | messages | Messages
  - e | obsidian | Obsidian
  - g | iPhone | iPhone Mirroring

other:
  - x | foo | Bar
`
	if got != want {
		t.Errorf("append mismatch:\n--got--\n%s\n--want--\n%s", got, want)
	}
}

func TestOverwriteFlatEntry(t *testing.T) {
	got, err := upsertFlatEntry(sampleFlat, "app", "e", "- e | notes | Obsidian Notes")
	if err != nil {
		t.Fatal(err)
	}
	want := `app:
  # key | label | app
  - w | WA | Whatsapp
  - W | messages | Messages
  - e | notes | Obsidian Notes

other:
  - x | foo | Bar
`
	if got != want {
		t.Errorf("overwrite mismatch:\n--got--\n%s\n--want--\n%s", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src/add-keymap && go test ./... -run 'TestAppendFlatEntry|TestOverwriteFlatEntry'`
Expected: FAIL — `undefined: upsertFlatEntry`.

- [ ] **Step 3: Write the implementation**

Append to `src/add-keymap/yamledit.go`:
```go
// upsertFlatEntry inserts newLine into the given flat section, or replaces the
// existing "- key | ..." line if key already exists. Indentation is two spaces.
// Comments and surrounding sections are preserved verbatim.
func upsertFlatEntry(text, section, key, newLine string) (string, error) {
	lines := strings.Split(text, "\n")
	inSection := false
	sectionStart := -1 // index of the section header line
	lastItem := -1     // index of last "- " item line in the section
	for i, line := range lines {
		stripped := strings.TrimSpace(line)
		if sectionHeaderRe.MatchString(stripped) {
			if strings.TrimSuffix(stripped, ":") == section {
				inSection = true
				sectionStart = i
			} else if inSection {
				break // left the section
			} else {
				inSection = false
			}
			continue
		}
		if !inSection {
			continue
		}
		if strings.HasPrefix(stripped, "- ") {
			lastItem = i
			if firstField(stripped[2:]) == key {
				lines[i] = "  " + newLine // overwrite in place, preserve indent
				return strings.Join(lines, "\n"), nil
			}
		}
	}
	if sectionStart == -1 {
		return "", &editError{"section not found: " + section}
	}
	insertAt := lastItem + 1
	if lastItem == -1 {
		insertAt = sectionStart + 1 // empty section: right after header
	}
	out := make([]string, 0, len(lines)+1)
	out = append(out, lines[:insertAt]...)
	out = append(out, "  "+newLine)
	out = append(out, lines[insertAt:]...)
	return strings.Join(out, "\n"), nil
}

type editError struct{ msg string }

func (e *editError) Error() string { return e.msg }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src/add-keymap && go test ./... -run 'TestAppendFlatEntry|TestOverwriteFlatEntry'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/add-keymap/yamledit.go src/add-keymap/yamledit_test.go
git commit -m "feat(karabiner): add-keymap flat-section upsert (append/overwrite)"
```

---

## Task 6: Hyper nested read + insert

**Files:**
- Modify: `src/add-keymap/yamledit.go`
- Modify: `src/add-keymap/yamledit_test.go`

- [ ] **Step 1: Write the failing test**

Append to `src/add-keymap/yamledit_test.go`:
```go
const sampleHyper = `hyper:
  h:
    -: left_arrow # ←
    shift: "!TStab" # prevTab

  j:
    -: down_arrow # ↓

misc:
  escape:
    -: "!Tcaps_lock" # caps
`

func TestHyperModsForKey(t *testing.T) {
	mods := hyperModsForKey(sampleHyper, "h")
	if !mods["-"] || !mods["shift"] {
		t.Errorf("expected - and shift mods for h, got %v", mods)
	}
	if len(hyperModsForKey(sampleHyper, "z")) != 0 {
		t.Errorf("expected no mods for absent key z")
	}
}

func TestUpsertHyperNewMod(t *testing.T) {
	got, err := upsertHyperEntry(sampleHyper, "h", "cmd", `"!Sleft_arrow"`, "sel")
	if err != nil {
		t.Fatal(err)
	}
	want := `hyper:
  h:
    -: left_arrow # ←
    shift: "!TStab" # prevTab
    cmd: "!Sleft_arrow" # sel

  j:
    -: down_arrow # ↓

misc:
  escape:
    -: "!Tcaps_lock" # caps
`
	if got != want {
		t.Errorf("hyper new-mod mismatch:\n--got--\n%s\n--want--\n%s", got, want)
	}
}

func TestUpsertHyperNewKey(t *testing.T) {
	got, err := upsertHyperEntry(sampleHyper, "m", "-", "spotlight", "find")
	if err != nil {
		t.Fatal(err)
	}
	want := `hyper:
  h:
    -: left_arrow # ←
    shift: "!TStab" # prevTab

  j:
    -: down_arrow # ↓

  m:
    -: spotlight # find

misc:
  escape:
    -: "!Tcaps_lock" # caps
`
	if got != want {
		t.Errorf("hyper new-key mismatch:\n--got--\n%s\n--want--\n%s", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src/add-keymap && go test ./... -run 'TestHyperModsForKey|TestUpsertHyperNewMod|TestUpsertHyperNewKey'`
Expected: FAIL — `undefined: hyperModsForKey` / `upsertHyperEntry`.

- [ ] **Step 3: Write the implementation**

Append to `src/add-keymap/yamledit.go`:
```go
// keyHeaderRe matches a 2-space-indented hyper key block header, e.g. "  h:".
var keyHeaderRe = regexp.MustCompile(`^  (\S+):\s*$`)

// modLineRe matches a 4-space-indented mod entry, e.g. `    shift: "!TStab" # prevTab`.
var modLineRe = regexp.MustCompile(`^    ([^:]+):`)

// hyperModsForKey returns the set of modifier slots already defined for a key
// under the top-level "hyper:" section.
func hyperModsForKey(text, key string) map[string]bool {
	mods := map[string]bool{}
	inHyper, inKey := false, false
	for _, line := range strings.Split(text, "\n") {
		stripped := strings.TrimSpace(line)
		if sectionHeaderRe.MatchString(stripped) {
			inHyper = stripped == "hyper:"
			inKey = false
			continue
		}
		if !inHyper {
			continue
		}
		if m := keyHeaderRe.FindStringSubmatch(line); m != nil {
			inKey = m[1] == key
			continue
		}
		if inKey {
			if m := modLineRe.FindStringSubmatch(line); m != nil {
				mods[strings.TrimSpace(m[1])] = true
			}
		}
	}
	return mods
}

// upsertHyperEntry inserts `<mod>: <action> # <label>` under the given key in
// the hyper section. If the key block does not exist, a new block is inserted at
// the end of the hyper section (before the next top-level section, e.g. misc:).
// If the mod already exists under the key, it is overwritten in place.
func upsertHyperEntry(text, key, mod, action, label string) (string, error) {
	lines := strings.Split(text, "\n")
	modLine := "    " + mod + ": " + action + " # " + label

	inHyper, inKey := false, false
	hyperStart := -1
	keyHeader := -1
	keyLastMod := -1
	hyperEnd := len(lines) // first line index after the hyper section
	for i, line := range lines {
		stripped := strings.TrimSpace(line)
		if sectionHeaderRe.MatchString(stripped) {
			if stripped == "hyper:" {
				inHyper = true
				hyperStart = i
			} else if inHyper {
				hyperEnd = i
				break
			}
			inKey = false
			continue
		}
		if !inHyper {
			continue
		}
		if m := keyHeaderRe.FindStringSubmatch(line); m != nil {
			if inKey && keyHeader != -1 {
				// leaving previous key
			}
			inKey = m[1] == key
			if inKey {
				keyHeader = i
				keyLastMod = i
			}
			continue
		}
		if inKey {
			if m := modLineRe.FindStringSubmatch(line); m != nil {
				if strings.TrimSpace(m[1]) == mod {
					lines[i] = modLine // overwrite
					return strings.Join(lines, "\n"), nil
				}
				keyLastMod = i
			} else if strings.TrimSpace(line) != "" {
				keyLastMod = i
			}
		}
	}
	if hyperStart == -1 {
		return "", &editError{"hyper section not found"}
	}

	if keyHeader != -1 {
		// Insert new mod after the key's last mod line.
		insertAt := keyLastMod + 1
		out := make([]string, 0, len(lines)+1)
		out = append(out, lines[:insertAt]...)
		out = append(out, modLine)
		out = append(out, lines[insertAt:]...)
		return strings.Join(out, "\n"), nil
	}

	// New key block: insert before hyperEnd. Trim one trailing blank line that
	// typically precedes the next section header so spacing stays consistent.
	insertAt := hyperEnd
	for insertAt-1 > hyperStart && strings.TrimSpace(lines[insertAt-1]) == "" {
		insertAt--
	}
	block := []string{"  " + key + ":", modLine, ""}
	out := make([]string, 0, len(lines)+len(block))
	out = append(out, lines[:insertAt]...)
	out = append(out, block...)
	out = append(out, lines[insertAt:]...)
	return strings.Join(out, "\n"), nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src/add-keymap && go test ./... -run 'TestHyperModsForKey|TestUpsertHyperNewMod|TestUpsertHyperNewKey'`
Expected: PASS. If spacing differs, adjust the blank-line trimming until fixtures match byte-for-byte.

- [ ] **Step 5: Commit**

```bash
git add src/add-keymap/yamledit.go src/add-keymap/yamledit_test.go
git commit -m "feat(karabiner): add-keymap hyper nested upsert"
```

---

## Task 7: Layer metadata + YAML-line builders

**Files:**
- Create: `src/add-keymap/layers.go`
- Test: `src/add-keymap/layers_test.go`

- [ ] **Step 1: Write the failing test**

`src/add-keymap/layers_test.go`:
```go
package main

import "testing"

func TestBuildFlatLine(t *testing.T) {
	cases := []struct {
		key, label, extra, want string
	}{
		{"g", "iPhone", "iPhone Mirroring", "- g | iPhone | iPhone Mirroring"},
		{"c", "switch", "!Cgrave_accent_and_tilde", "- c | switch | !Cgrave_accent_and_tilde"},
		{"o", "1p", "", "- o | 1p"},
	}
	for _, c := range cases {
		if got := buildFlatLine(c.key, c.label, c.extra); got != want(c.want) {
			t.Errorf("buildFlatLine(%q,%q,%q) = %q want %q", c.key, c.label, c.extra, got, c.want)
		}
	}
}

func want(s string) string { return s }

func TestValidateGokuCombo(t *testing.T) {
	if err := validateGokuCombo("!Cgrave_accent_and_tilde"); err != nil {
		t.Errorf("valid combo rejected: %v", err)
	}
	if err := validateGokuCombo("Cgrave"); err == nil {
		t.Errorf("combo without leading ! should fail")
	}
	if err := validateGokuCombo("!Zfoo"); err == nil {
		t.Errorf("combo with unknown modifier Z should fail")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src/add-keymap && go test ./... -run 'TestBuildFlatLine|TestValidateGokuCombo'`
Expected: FAIL — `undefined: buildFlatLine` / `validateGokuCombo`.

- [ ] **Step 3: Write the implementation**

`src/add-keymap/layers.go`:
```go
package main

import (
	"fmt"
	"strings"
)

// Layer describes one addressable layer family.
type Layer struct {
	ID         string // "app","workspace","l1","l2","l3","hyper"
	File       string // YAML filename relative to the karabiner source dir
	Section    string // section name within that file (set per-variant for workspace)
	AllowUpper bool   // uppercase = shift variant (app/workspace)
}

// layerByID returns base metadata for a layer id. Workspace section is decided
// at prompt time (base vs shift); File stays constant.
var layerByID = map[string]Layer{
	"app":       {ID: "app", File: "config/app.yaml", Section: "app", AllowUpper: true},
	"workspace": {ID: "workspace", File: "config/help-text.yaml", Section: "workspace", AllowUpper: true},
	"l1":        {ID: "l1", File: "config/shortcuts.yaml", Section: "l1"},
	"l2":        {ID: "l2", File: "config/shortcuts.yaml", Section: "l2"},
	"l3":        {ID: "l3", File: "config/shortcuts.yaml", Section: "l3"},
	"hyper":     {ID: "hyper", File: "config/hyperkeys.yaml", Section: "hyper"},
}

var layerOrder = []string{"app", "workspace", "l1", "l2", "l3", "hyper"}

// buildFlatLine renders a "- key | label[ | extra]" YAML item (no indent).
func buildFlatLine(key, label, extra string) string {
	if strings.TrimSpace(extra) == "" {
		return fmt.Sprintf("- %s | %s", key, label)
	}
	return fmt.Sprintf("- %s | %s | %s", key, label, extra)
}

// hyperModSlots is the ordered set of modifier slots offered for hyper entries.
var hyperModSlots = []string{"-", "shift", "cmd", "opt", "ctrl", "opt+cmd", "ctrl+shift"}

// validModLetters are the goku modifier letters accepted after a leading ! or #.
const validModLetters = "CTOSFQWRP!#"

// validateGokuCombo does a light check that s looks like a goku combo:
// starts with ! or #, and every leading modifier char is known.
func validateGokuCombo(s string) error {
	if s == "" {
		return fmt.Errorf("combo is empty")
	}
	if s[0] != '!' && s[0] != '#' {
		return fmt.Errorf("goku combo must start with ! or # (got %q)", s)
	}
	// Consume leading modifier letters; the rest is the key name.
	i := 0
	for i < len(s) && strings.IndexByte(validModLetters, s[i]) >= 0 {
		i++
	}
	if i >= len(s) {
		return fmt.Errorf("combo %q has no key after modifiers", s)
	}
	return nil
}

// hyperAction renders a hyper action value: a quoted scalar, or a JSON-style
// sequence if the user supplied a comma-separated list.
func hyperAction(raw string) string {
	raw = strings.TrimSpace(raw)
	if strings.Contains(raw, ",") {
		parts := strings.Split(raw, ",")
		quoted := make([]string, 0, len(parts))
		for _, p := range parts {
			quoted = append(quoted, `"`+strings.TrimSpace(p)+`"`)
		}
		return "[" + strings.Join(quoted, ", ") + "]"
	}
	// Quote combos/symbols; leave bare identifiers (e.g. left_arrow) unquoted.
	if strings.HasPrefix(raw, "!") || strings.HasPrefix(raw, "#") {
		return `"` + raw + `"`
	}
	return raw
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src/add-keymap && go test ./... -run 'TestBuildFlatLine|TestValidateGokuCombo'`
Expected: PASS.

- [ ] **Step 5: Add a test for hyperAction and run all package tests**

Append to `src/add-keymap/layers_test.go`:
```go
func TestHyperAction(t *testing.T) {
	if hyperAction("left_arrow") != "left_arrow" {
		t.Errorf("bare identifier should stay unquoted")
	}
	if hyperAction("!Sleft_arrow") != `"!Sleft_arrow"` {
		t.Errorf("combo should be quoted")
	}
	if hyperAction("!Sup_arrow, !Sup_arrow") != `["!Sup_arrow", "!Sup_arrow"]` {
		t.Errorf("sequence rendering wrong: %s", hyperAction("!Sup_arrow, !Sup_arrow"))
	}
}
```
Run: `cd src/add-keymap && go test ./...`
Expected: PASS (all tasks' tests).

- [ ] **Step 6: Commit**

```bash
git add src/add-keymap/layers.go src/add-keymap/layers_test.go
git commit -m "feat(karabiner): add-keymap layer metadata + line builders"
```

---

## Task 8: Prompt helpers

**Files:**
- Create: `src/add-keymap/prompt.go`

(These wrap stdin; covered by manual e2e in Task 11 rather than unit tests.)

- [ ] **Step 1: Write the implementation**

`src/add-keymap/prompt.go`:
```go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

var stdin = bufio.NewReader(os.Stdin)

// readLine reads one trimmed line from stdin.
func readLine() string {
	s, _ := stdin.ReadString('\n')
	return strings.TrimSpace(s)
}

// askMenu prints a numbered menu and returns the chosen item (loops until valid).
func askMenu(title string, options []string) string {
	for {
		fmt.Println(title)
		for i, o := range options {
			fmt.Printf("  %d) %s\n", i+1, o)
		}
		fmt.Print("> ")
		n, err := strconv.Atoi(readLine())
		if err == nil && n >= 1 && n <= len(options) {
			return options[n-1]
		}
		fmt.Println("Please enter a number from the list.")
	}
}

// askText prompts for a non-empty line (loops until non-empty).
func askText(prompt string) string {
	for {
		fmt.Printf("%s ", prompt)
		s := readLine()
		if s != "" {
			return s
		}
		fmt.Println("Value cannot be empty.")
	}
}

// askOptionalText prompts for a line that may be empty.
func askOptionalText(prompt string) string {
	fmt.Printf("%s ", prompt)
	return readLine()
}

// confirm asks a [y/N] question; default is No.
func confirm(prompt string) bool {
	fmt.Printf("%s [y/N] ", prompt)
	s := strings.ToLower(readLine())
	return s == "y" || s == "yes"
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd src/add-keymap && go build ./...`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/add-keymap/prompt.go
git commit -m "feat(karabiner): add-keymap stdin prompt helpers"
```

---

## Task 9: Source-dir resolution + deploy

**Files:**
- Create: `src/add-keymap/deploy.go`

- [ ] **Step 1: Write the implementation**

`src/add-keymap/deploy.go`:
```go
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// resolveSourceDir returns the chezmoi *source* path of the karabiner config dir.
// Primary: `chezmoi source-path ~/.config/karabiner`. Fallback: two levels up
// from the running binary (…/karabiner/scripts/add-keymap -> …/karabiner).
func resolveSourceDir() (string, error) {
	home, _ := os.UserHomeDir()
	target := filepath.Join(home, ".config", "karabiner")
	out, err := exec.Command("chezmoi", "source-path", target).Output()
	if err == nil {
		dir := strings.TrimSpace(string(out))
		if dir != "" {
			if _, statErr := os.Stat(filepath.Join(dir, "build.sh")); statErr == nil {
				return dir, nil
			}
		}
	}
	exe, exeErr := os.Executable()
	if exeErr == nil {
		cand := filepath.Dir(filepath.Dir(exe)) // scripts/ -> karabiner/
		if _, statErr := os.Stat(filepath.Join(cand, "build.sh")); statErr == nil {
			return cand, nil
		}
	}
	return "", fmt.Errorf("could not locate karabiner source dir (chezmoi source-path failed: %v)", err)
}

// runIn runs name+args in dir, streaming stdout/stderr to the terminal.
func runIn(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

// build runs ./build.sh in the source dir.
func build(srcDir string) error {
	fmt.Println("\n→ Building (./build.sh)…")
	return runIn(srcDir, "./build.sh")
}

// deploy runs chezmoi apply then goku. Never uses --force.
func deploy(srcDir string) error {
	fmt.Println("\n→ chezmoi apply…")
	if err := runIn(srcDir, "chezmoi", "apply"); err != nil {
		return err
	}
	fmt.Println("\n→ goku…")
	return runIn(srcDir, "goku")
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd src/add-keymap && go build ./...`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/add-keymap/deploy.go
git commit -m "feat(karabiner): add-keymap source-dir resolution + deploy"
```

---

## Task 10: Wire the interactive flow in main.go

**Files:**
- Modify: `src/add-keymap/main.go`

- [ ] **Step 1: Replace main.go with the full flow**

`src/add-keymap/main.go`:
```go
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "\nerror:", err)
		os.Exit(1)
	}
}

func run() error {
	srcDir, err := resolveSourceDir()
	if err != nil {
		return err
	}
	fmt.Println("add-keymap — karabiner source:", srcDir)

	layerID := askMenu("\nWhich layer?", layerOrder)
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
		if askMenu("\nBase or shift variant?", []string{"base (opt+key)", "shift (opt+shift+key)"}) == "shift (opt+shift+key)" {
			section = "workspace-shift"
		}
	}

	key := promptKey(text, section, layer.AllowUpper)

	label := askText("\nLabel (short, shown in help overlay):")

	var extra string
	switch layer.ID {
	case "app":
		extra = promptAppTarget()
	case "workspace":
		extra = askText("\nAerospace command (e.g. 'workspace 1'):")
	case "l1", "l2", "l3":
		extra = promptShortcutTarget()
	}

	line := buildFlatLine(key, label, extra)
	fmt.Printf("\nWill add to %s [%s]:\n  %s\n", layer.File, section, line)
	if !confirm("Proceed?") {
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

// runHyper handles the nested hyperkeys.yaml.
func runHyper(srcDir string, layer Layer) error {
	path := filepath.Join(srcDir, layer.File)
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(b)

	key := promptHyperKey(text)
	existing := hyperModsForKey(text, key)

	var mod string
	for {
		mod = askMenu("\nModifier slot:", hyperModSlots)
		if !existing[mod] {
			break
		}
		if confirm(fmt.Sprintf("hyper+%s already maps %q — overwrite?", key, mod)) {
			break
		}
	}

	rawAction := askText("\nAction (goku key code, or comma-separated sequence):")
	if strings.HasPrefix(rawAction, "!") || strings.HasPrefix(rawAction, "#") {
		if err := validateGokuCombo(rawAction); err != nil {
			return err
		}
	}
	label := askText("Label (help overlay):")
	action := hyperAction(rawAction)

	fmt.Printf("\nWill add under hyper.%s:\n    %s: %s # %s\n", key, mod, action, label)
	if !confirm("Proceed?") {
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

// promptKey loops until a valid, non-colliding (or overwrite-confirmed) key.
func promptKey(text, section string, allowUpper bool) string {
	existing := sectionKeys(text, section)
	for {
		key := askText("\nKey to map:")
		if err := validateKey(key, allowUpper); err != nil {
			fmt.Println(" ", err)
			continue
		}
		if existing[key] {
			if confirm(fmt.Sprintf("%q is already mapped in this layer — overwrite?", key)) {
				return key
			}
			continue
		}
		return key
	}
}

// promptHyperKey validates a hyper key (no shift variants).
func promptHyperKey(text string) string {
	for {
		key := askText("\nKey to map (under CapsLock/hyper):")
		if err := validateKey(key, false); err != nil {
			fmt.Println(" ", err)
			continue
		}
		return key
	}
}

// promptAppTarget returns the YAML extra field for an app entry.
func promptAppTarget() string {
	if askMenu("\nTarget type:", []string{"App (open -a)", "Raw goku combo (!…)"}) == "Raw goku combo (!…)" {
		for {
			c := askText("Goku combo (e.g. !Cgrave_accent_and_tilde):")
			if err := validateGokuCombo(c); err != nil {
				fmt.Println(" ", err)
				continue
			}
			return c
		}
	}
	return askText("App name (as in /Applications, e.g. 'Microsoft Teams'):")
}

// promptShortcutTarget returns the YAML extra field for an l1/l2/l3 entry.
func promptShortcutTarget() string {
	choice := askMenu("\nMapping type:", []string{
		"F-key pool (auto-assign a combo to bind in Alfred/KM)",
		"Direct: open an app (open:App)",
		"Direct: raw goku combo (!…)",
	})
	switch {
	case strings.HasPrefix(choice, "F-key"):
		return "" // blank → pool
	case strings.HasPrefix(choice, "Direct: open"):
		return "open:" + askText("App name:")
	default:
		for {
			c := askText("Goku combo (e.g. !CSf13):")
			if err := validateGokuCombo(c); err != nil {
				fmt.Println(" ", err)
				continue
			}
			return c
		}
	}
}

// reportFlat prints the resulting mapping after a build.
func reportFlat(srcDir string, layer Layer, section, key, extra string) {
	switch layer.ID {
	case "l1", "l2", "l3":
		if strings.TrimSpace(extra) == "" {
			pool, err := readPool(filepath.Join(srcDir, "data", "fkey-pool.json"))
			if err == nil {
				if combo, ok := comboForKey(pool, layer.ID, key); ok {
					fmt.Printf("\n✓ Mapped: %s + %s → %s   (bind this in Alfred/KM)\n", layer.ID, key, combo)
					return
				}
			}
			fmt.Printf("\n✓ Added %s + %s to the F-key pool (see data/fkey-pool.json).\n", layer.ID, key)
		} else {
			fmt.Printf("\n✓ Mapped: %s + %s → %s\n", layer.ID, key, extra)
		}
	case "app":
		fmt.Printf("\n✓ Mapped: RightOpt + %s → %s\n", key, extra)
	case "workspace":
		mod := "LeftOpt"
		if section == "workspace-shift" {
			mod = "LeftOpt+Shift"
		}
		fmt.Printf("\n✓ Mapped: %s + %s → %s\n", mod, key, extra)
	}
}

// maybeDeploy offers to chezmoi apply + goku.
func maybeDeploy(srcDir string) error {
	if confirm("\nDeploy now (chezmoi apply && goku)?") {
		return deploy(srcDir)
	}
	fmt.Println("\nSkipped. To deploy later:\n  chezmoi apply && goku")
	return nil
}
```

- [ ] **Step 2: Verify it compiles and tests still pass**

Run: `cd src/add-keymap && go build ./... && go test ./...`
Expected: builds; all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add src/add-keymap/main.go
git commit -m "feat(karabiner): add-keymap interactive flow"
```

---

## Task 11: Build binary, manual e2e, README

**Files:**
- Create: `scripts/executable_add-keymap` (committed binary)
- Modify: `README.md`

- [ ] **Step 1: Build the committed binary**

Run: `cd src/add-keymap && ./build.sh`
Expected: prints `Built scripts/executable_add-keymap`; `ls -la ../../scripts/executable_add-keymap` shows the file.

- [ ] **Step 2: Manual end-to-end on a scratch copy**

Run:
```bash
cd "$(mktemp -d)" && cp -R /Users/zaid/.local/share/chezmoi/.worktrees/main-4861/dot_config/private_karabiner/* . 
./scripts/executable_add-keymap   # or: go run ./../../src/add-keymap
```
Walk one entry per layer:
- l1 → key `z` → F-key pool → confirm → build → expect `✓ Mapped: l1 + z → <combo>`; decline deploy.
- app → key `G` (shift) → App `Finder` → confirm → build → expect mapping line.
- hyper → key `m` → mod `cmd` → action `spotlight` → label `find` → build.
After each, `git diff` (in the scratch copy) the YAML to confirm comments/grouping preserved and `./build.sh` regenerated `karabiner.edn` without errors.
Expected: each flow completes; reported combo matches `data/fkey-pool.json`.

- [ ] **Step 3: Add README usage section**

Add to `README.md` after the "Shortcut Layers" section:
```markdown
## Interactive: `add-keymap`

Instead of hand-editing YAML, run the wizard to add a keymap to any layer:

```bash
./scripts/executable_add-keymap     # or, deployed: ~/.config/karabiner/scripts/add-keymap
```

It prompts for layer → key (with validation + collision check) → target, writes
the right YAML, runs `./build.sh`, reports the assigned key/F-key combo, and
offers to `chezmoi apply && goku`.

**Rebuild the binary after changing Go source:**
```bash
./src/add-keymap/build.sh
```
Requires Go (build-time only; the committed binary needs nothing at runtime).
```

- [ ] **Step 4: Commit**

```bash
git add scripts/executable_add-keymap README.md
git commit -m "feat(karabiner): build add-keymap binary + document usage"
```

---

## Self-Review Notes

- **Spec coverage:** layer table (Task 7/10), validated key + collision (Task 3/10), per-layer targets incl. pool vs direct (Task 10), comment-preserving YAML write (Task 5/6), build delegation + pool readback reporting (Task 2/9/10), deploy without `--force` (Task 9/10), source-dir via `chezmoi source-path` with fallback (Task 9), tests for pure logic + manual e2e (Tasks 2-7, 11). All spec sections map to a task.
- **Type consistency:** `upsertFlatEntry`, `upsertHyperEntry`, `sectionKeys`, `hyperModsForKey`, `slotToCombo`, `comboForKey`, `readPool`, `validateKey`, `gokuName`, `buildFlatLine`, `validateGokuCombo`, `hyperAction`, `Layer`/`layerByID`/`layerOrder`, prompt helpers, and deploy funcs are referenced consistently across tasks.
- **Note on `data/fkey-pool.json`:** allocation happens inside `./build.sh` (Python); the wizard only reads it back. The reported combo therefore reflects the real assignment, not a Go-side guess.
