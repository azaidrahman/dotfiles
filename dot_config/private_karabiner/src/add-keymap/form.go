package main

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/bubbles/key"
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
	for _, s := range symbolKeys {
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

// backEscKeyMap is the default huh keymap with consistent navigation across
// every screen: Esc / shift+tab go back, and on text Input fields ↑/↓ also move
// between fields (so a focused input doesn't trap you — you can arrow out or Esc
// back without it interfering with typed letters; ↑/↓/Esc aren't text). Selects
// keep ↑/↓ for choosing options. Esc is disabled on the first screen and yields
// to select-filter mode, so it can't quit; Ctrl-C quits.
func backEscKeyMap() *huh.KeyMap {
	km := huh.NewDefaultKeyMap()
	back := key.NewBinding(key.WithKeys("esc", "shift+tab"), key.WithHelp("esc", "back"))
	km.Select.Prev = back
	km.Confirm.Prev = back
	km.Note.Prev = back
	km.Input.Prev = key.NewBinding(key.WithKeys("esc", "shift+tab", "up"), key.WithHelp("esc/↑", "back"))
	km.Input.Next = key.NewBinding(key.WithKeys("enter", "tab", "down"), key.WithHelp("↓/enter", "next"))
	return km
}

// runForm runs a huh form, mapping a user abort (Ctrl-C) to the wizard's
// existing "cancelled" error so callers handle it uniformly. Esc navigates back.
func runForm(groups ...*huh.Group) error {
	err := huh.NewForm(groups...).WithKeyMap(backEscKeyMap()).Run()
	if errors.Is(err, huh.ErrUserAborted) {
		return fmt.Errorf("cancelled")
	}
	return err
}
