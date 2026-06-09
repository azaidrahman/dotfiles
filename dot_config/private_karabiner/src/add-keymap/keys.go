package main

import (
	"fmt"
	"strings"
)

// specialNames (symbol -> goku key name) and longNames (accepted multi-char key
// tokens) are loaded from data/keymap-tables.json by loadTables; see tables.go.

const qwertyLetters = "abcdefghijklmnopqrstuvwxyz"
const digits = "0123456789"

// gokuName returns the goku key name for a YAML key token (symbol or already long).
func gokuName(key string) string {
	if long, ok := specialNames[key]; ok {
		return long
	}
	return key
}

// validateKey checks a key token is a usable single key.
// allowUpper permits an uppercase letter (the shift variant, used by app/workspace).
func validateKey(key string, allowUpper bool) error {
	if key == "" {
		return fmt.Errorf("key is empty")
	}
	if longNames[key] {
		return nil
	}
	if len(key) == 1 {
		r := key[0]
		if strings.IndexByte(qwertyLetters, r|0x20) >= 0 {
			if r >= 'A' && r <= 'Z' && !allowUpper {
				return fmt.Errorf("uppercase key %q not allowed in this layer", key)
			}
			return nil
		}
		if strings.IndexByte(digits, r) >= 0 {
			return nil
		}
	}
	return fmt.Errorf("invalid key %q (use a letter, digit, or one of: - = [ ] ; ' , . / \\ ` space)", key)
}
