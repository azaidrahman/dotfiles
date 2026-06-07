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
