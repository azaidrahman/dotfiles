package main

import (
	"os"
	"path/filepath"
	"testing"
)

// TestMain loads the shared lookup tables from the repo's canonical
// data/keymap-tables.json before any test runs, so unit tests of validateKey,
// gokuName, and slotToCombo see populated tables (in production loadTables is
// called from runCLI/run after the source dir is resolved). The package dir is
// src/add-keymap, so the source root is two levels up.
func TestMain(m *testing.M) {
	root, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		panic(err)
	}
	if err := loadTables(root); err != nil {
		panic("loadTables for tests: " + err.Error())
	}
	os.Exit(m.Run())
}
