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
