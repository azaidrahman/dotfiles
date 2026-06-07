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
