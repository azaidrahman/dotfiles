package main

import "testing"

func TestFreeKeyHint(t *testing.T) {
	existing := map[string]bool{"a": true, "b": true, "-": true}
	got := freeKeyHint(existing)
	want := "free: c d e f g h i j k l m n o p q r s t u v w x y z " +
		"0 1 2 3 4 5 6 7 8 9 = [ ] ; ' , . / \\ ` space"
	if got != want {
		t.Fatalf("freeKeyHint mismatch:\n got: %q\nwant: %q", got, want)
	}
}

func TestFreeKeyHintNoneFree(t *testing.T) {
	existing := map[string]bool{}
	for _, r := range qwertyLetters {
		existing[string(r)] = true
	}
	for _, r := range digits {
		existing[string(r)] = true
	}
	for _, s := range symbolKeys {
		existing[s] = true
	}
	if got := freeKeyHint(existing); got != "free: (none — all keys taken)" {
		t.Fatalf("expected none-free sentinel, got %q", got)
	}
}
