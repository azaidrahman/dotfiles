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
