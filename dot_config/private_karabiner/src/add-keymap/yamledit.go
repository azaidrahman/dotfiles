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
