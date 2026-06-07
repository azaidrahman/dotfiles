package main

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/huh"
)

// Layer describes one addressable layer family.
type Layer struct {
	ID         string // "app","workspace","l1","l2","l3","hyper"
	File       string // YAML filename relative to the karabiner source dir
	Section    string // section name within that file (set per-variant for workspace)
	AllowUpper bool   // uppercase = shift variant (app/workspace)
	Desc       string // how the layer is triggered (shown in the layer picker)
}

// layerByID returns base metadata for a layer id. Workspace section is decided
// at prompt time (base vs shift); File stays constant.
var layerByID = map[string]Layer{
	"app":       {ID: "app", File: "config/app.yaml", Section: "app", AllowUpper: true, Desc: "hold Right ⌥, then a key launches an app"},
	"workspace": {ID: "workspace", File: "config/help-text.yaml", Section: "workspace", AllowUpper: true, Desc: "hold Left ⌥, aerospace window/workspace control"},
	"l1":        {ID: "l1", File: "config/shortcuts.yaml", Section: "l1", Desc: "Right ⌥ + ⇧ shortcut layer"},
	"l2":        {ID: "l2", File: "config/shortcuts.yaml", Section: "l2", Desc: "Right ⌥ + ⌃ shortcut layer"},
	"l3":        {ID: "l3", File: "config/shortcuts.yaml", Section: "l3", Desc: "Right ⌥ + ⌘ shortcut layer"},
	"hyper":     {ID: "hyper", File: "config/hyperkeys.yaml", Section: "hyper", Desc: "CapsLock held (⌘⌃⌥⇧)"},
}

var layerOrder = []string{"app", "workspace", "l1", "l2", "l3", "hyper"}

// layerOptions builds the layer picker entries: "id — how it's triggered".
// The option value stays the bare id so layerByID lookups keep working.
func layerOptions() []huh.Option[string] {
	opts := make([]huh.Option[string], 0, len(layerOrder))
	for _, id := range layerOrder {
		l := layerByID[id]
		opts = append(opts, huh.NewOption(fmt.Sprintf("%-9s — %s", l.ID, l.Desc), l.ID))
	}
	return opts
}

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
const validModLetters = "CTOSFQWRP"

// validateGokuCombo does a light check that s looks like a goku combo:
// starts with ! or #, and every leading modifier char is known.
func validateGokuCombo(s string) error {
	if s == "" {
		return fmt.Errorf("combo is empty")
	}
	if s[0] != '!' && s[0] != '#' {
		return fmt.Errorf("goku combo must start with ! or # (got %q)", s)
	}
	// After the leading ! or #, consume uppercase modifier letters and validate each.
	i := 1
	for i < len(s) && s[i] >= 'A' && s[i] <= 'Z' {
		if strings.IndexByte(validModLetters, s[i]) < 0 {
			return fmt.Errorf("combo %q contains unknown modifier letter %q", s, rune(s[i]))
		}
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
