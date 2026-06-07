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

func TestSlotToComboOutOfRange(t *testing.T) {
	// 112 is one past the last valid slot (7 fkeys * 16 mods). Must not panic.
	if got := slotToCombo(112); got != "slot#112" {
		t.Errorf("slotToCombo(112) = %q, want slot#112", got)
	}
	if got := slotToCombo(-1); got != "slot#-1" {
		t.Errorf("slotToCombo(-1) = %q, want slot#-1", got)
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
