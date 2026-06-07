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
