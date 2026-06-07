package main

import (
	"regexp"
	"strings"
)

var sectionHeaderRe = regexp.MustCompile(`^[a-z][\w-]*:\s*$`)

// firstField returns the trimmed key (first |-field) of a "- key | ..." item.
func firstField(itemBody string) string {
	parts := strings.SplitN(itemBody, "|", 2)
	return strings.TrimSpace(parts[0])
}

// sectionKeys returns the set of keys present in a flat section of YAML text.
func sectionKeys(text, section string) map[string]bool {
	keys := map[string]bool{}
	inSection := false
	for _, line := range strings.Split(text, "\n") {
		stripped := strings.TrimSpace(line)
		if sectionHeaderRe.MatchString(stripped) {
			inSection = strings.TrimSuffix(stripped, ":") == section
			continue
		}
		if !inSection || stripped == "" || strings.HasPrefix(stripped, "#") {
			continue
		}
		if strings.HasPrefix(stripped, "- ") {
			keys[firstField(stripped[2:])] = true
		}
	}
	return keys
}

// upsertFlatEntry inserts newLine into the given flat section, or replaces the
// existing "- key | ..." line if key already exists. Indentation is two spaces.
// Comments and surrounding sections are preserved verbatim.
func upsertFlatEntry(text, section, key, newLine string) (string, error) {
	lines := strings.Split(text, "\n")
	inSection := false
	sectionStart := -1 // index of the section header line
	lastItem := -1     // index of last "- " item line in the section
	for i, line := range lines {
		stripped := strings.TrimSpace(line)
		if sectionHeaderRe.MatchString(stripped) {
			if strings.TrimSuffix(stripped, ":") == section {
				inSection = true
				sectionStart = i
			} else if inSection {
				break // left the section
			} else {
				inSection = false
			}
			continue
		}
		if !inSection {
			continue
		}
		if strings.HasPrefix(stripped, "- ") {
			lastItem = i
			if firstField(stripped[2:]) == key {
				lines[i] = "  " + newLine // overwrite in place, preserve indent
				return strings.Join(lines, "\n"), nil
			}
		}
	}
	if sectionStart == -1 {
		return "", &editError{"section not found: " + section}
	}
	insertAt := lastItem + 1
	if lastItem == -1 {
		insertAt = sectionStart + 1 // empty section: right after header
	}
	out := make([]string, 0, len(lines)+1)
	out = append(out, lines[:insertAt]...)
	out = append(out, "  "+newLine)
	out = append(out, lines[insertAt:]...)
	return strings.Join(out, "\n"), nil
}

type editError struct{ msg string }

func (e *editError) Error() string { return e.msg }

// keyHeaderRe matches a 2-space-indented hyper key block header, e.g. "  h:".
var keyHeaderRe = regexp.MustCompile(`^  (\S+):\s*$`)

// modLineRe matches a 4-space-indented mod entry, e.g. `    shift: "!TStab" # prevTab`.
var modLineRe = regexp.MustCompile(`^    ([^:]+):`)

// hyperModsForKey returns the set of modifier slots already defined for a key
// under the top-level "hyper:" section.
func hyperModsForKey(text, key string) map[string]bool {
	mods := map[string]bool{}
	inHyper, inKey := false, false
	for _, line := range strings.Split(text, "\n") {
		// Check 2-space key headers before stripped section headers to avoid
		// misidentifying "  h:" (stripped: "h:") as a top-level section.
		if inHyper {
			if m := keyHeaderRe.FindStringSubmatch(line); m != nil {
				inKey = m[1] == key
				continue
			}
		}
		stripped := strings.TrimSpace(line)
		if sectionHeaderRe.MatchString(stripped) {
			inHyper = stripped == "hyper:"
			inKey = false
			continue
		}
		if !inHyper {
			continue
		}
		if inKey {
			if m := modLineRe.FindStringSubmatch(line); m != nil {
				mods[strings.TrimSpace(m[1])] = true
			}
		}
	}
	return mods
}

// upsertHyperEntry inserts `<mod>: <action> # <label>` under the given key in
// the hyper section. If the key block does not exist, a new block is inserted at
// the end of the hyper section (before the next top-level section, e.g. misc:).
// If the mod already exists under the key, it is overwritten in place.
func upsertHyperEntry(text, key, mod, action, label string) (string, error) {
	lines := strings.Split(text, "\n")
	modLine := "    " + mod + ": " + action + " # " + label

	inHyper, inKey := false, false
	hyperStart := -1
	keyHeader := -1
	keyLastMod := -1
	hyperEnd := len(lines) // first line index after the hyper section
	for i, line := range lines {
		// Check 2-space key headers before stripped section headers to avoid
		// misidentifying "  h:" (stripped: "h:") as a top-level section.
		if inHyper {
			if m := keyHeaderRe.FindStringSubmatch(line); m != nil {
				inKey = m[1] == key
				if inKey {
					keyHeader = i
					keyLastMod = i
				}
				continue
			}
		}
		stripped := strings.TrimSpace(line)
		if sectionHeaderRe.MatchString(stripped) {
			if stripped == "hyper:" {
				inHyper = true
				hyperStart = i
			} else if inHyper {
				hyperEnd = i
				break
			}
			inKey = false
			continue
		}
		if !inHyper {
			continue
		}
		if inKey {
			if m := modLineRe.FindStringSubmatch(line); m != nil {
				if strings.TrimSpace(m[1]) == mod {
					lines[i] = modLine // overwrite
					return strings.Join(lines, "\n"), nil
				}
				keyLastMod = i
			} else if strings.TrimSpace(line) != "" {
				keyLastMod = i
			}
		}
	}
	if hyperStart == -1 {
		return "", &editError{"hyper section not found"}
	}

	if keyHeader != -1 {
		// Insert new mod after the key's last mod line.
		insertAt := keyLastMod + 1
		out := make([]string, 0, len(lines)+1)
		out = append(out, lines[:insertAt]...)
		out = append(out, modLine)
		out = append(out, lines[insertAt:]...)
		return strings.Join(out, "\n"), nil
	}

	// New key block: insert before hyperEnd (the first line of the next section).
	// The blank line already present before the next section becomes the blank
	// line separating the previous last key from the new key block.
	insertAt := hyperEnd
	block := []string{"  " + key + ":", modLine, ""}
	out := make([]string, 0, len(lines)+len(block))
	out = append(out, lines[:insertAt]...)
	out = append(out, block...)
	out = append(out, lines[insertAt:]...)
	return strings.Join(out, "\n"), nil
}
