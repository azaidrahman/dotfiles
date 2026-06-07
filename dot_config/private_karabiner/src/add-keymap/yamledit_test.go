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
