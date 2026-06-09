package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Lookup tables shared with the Python build (lib/tables.py). The single source
// of truth is data/keymap-tables.json; loadTables populates these package-level
// vars from it so the CLI's key validation and slot rendering always match what
// generate.py emits. They start empty and MUST be loaded (loadTables) once the
// source dir is known, before any key validation or slot rendering.
var (
	specialNames = map[string]string{}
	longNames    = map[string]bool{}
	fkeyPool     []string
	allMods      []modCombo
)

// modCombo is one (human, goku) modifier-prefix pair from all_mods.
type modCombo struct{ human, goku string }

// tablesFile mirrors the on-disk shape of data/keymap-tables.json.
type tablesFile struct {
	GokuNames map[string]string `json:"goku_names"`
	FkeyPool  []string          `json:"fkey_pool"`
	AllMods   [][]string        `json:"all_mods"`
}

// loadTables reads data/keymap-tables.json from the karabiner source dir and
// populates the package-level lookup tables. Call once after resolveSourceDir,
// before validateKey/gokuName/slotToCombo are used.
func loadTables(srcDir string) error {
	b, err := os.ReadFile(filepath.Join(srcDir, "data", "keymap-tables.json"))
	if err != nil {
		return fmt.Errorf("reading keymap tables: %w", err)
	}
	var t tablesFile
	if err := json.Unmarshal(b, &t); err != nil {
		return fmt.Errorf("parsing keymap tables: %w", err)
	}
	if len(t.GokuNames) == 0 || len(t.FkeyPool) == 0 || len(t.AllMods) == 0 {
		return fmt.Errorf("keymap tables incomplete (goku_names/fkey_pool/all_mods)")
	}

	specialNames = t.GokuNames
	longNames = make(map[string]bool, len(specialNames)*2)
	for sym, long := range specialNames {
		longNames[sym] = true
		longNames[long] = true
	}
	fkeyPool = t.FkeyPool
	allMods = make([]modCombo, len(t.AllMods))
	for i, m := range t.AllMods {
		if len(m) != 2 {
			return fmt.Errorf("all_mods[%d] must be a [human, goku] pair", i)
		}
		allMods[i] = modCombo{human: m[0], goku: m[1]}
	}
	return nil
}
