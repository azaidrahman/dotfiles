package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// Mirrors FKEY_POOL and ALL_MODS in lib/pool.py. Pool *allocation* stays in
// Python (generate.py); this table only renders an already-assigned slot for
// display. Keep in sync with lib/pool.py if that table changes.
var fkeyPool = []string{"f13", "f14", "f16", "f17", "f18", "f19", "f20"}

var allMods = []struct{ human, goku string }{
	{"", ""},
	{"ctrl+", "!T"},
	{"cmd+", "!C"},
	{"opt+", "!O"},
	{"ctrl+cmd+", "!CT"},
	{"ctrl+opt+", "!TO"},
	{"cmd+opt+", "!CO"},
	{"ctrl+cmd+opt+", "!CTO"},
	{"shift+", "!S"},
	{"ctrl+shift+", "!TS"},
	{"cmd+shift+", "!CS"},
	{"opt+shift+", "!OS"},
	{"ctrl+cmd+shift+", "!CTS"},
	{"ctrl+opt+shift+", "!TOS"},
	{"cmd+opt+shift+", "!COS"},
	{"ctrl+cmd+opt+shift+", "!CTOS"},
}

// slotToCombo renders a pool slot index as a human combo like "cmd+F16".
// An out-of-range slot (only reachable from a corrupt fkey-pool.json) renders
// defensively rather than panicking.
func slotToCombo(slot int) string {
	if slot < 0 || slot >= len(fkeyPool)*len(allMods) {
		return fmt.Sprintf("slot#%d", slot)
	}
	fkey := fkeyPool[slot/len(allMods)]
	mod := allMods[slot%len(allMods)]
	return mod.human + strings.ToUpper(fkey)
}

// readPool loads data/fkey-pool.json as a layer:key -> slot map.
// Missing file yields an empty map (not an error).
func readPool(path string) (map[string]int, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return map[string]int{}, nil
	}
	if err != nil {
		return nil, err
	}
	m := map[string]int{}
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, err
	}
	return m, nil
}

// comboForKey returns the rendered combo for a (layer,key) if assigned.
func comboForKey(pool map[string]int, layer, key string) (string, bool) {
	slot, ok := pool[layer+":"+key]
	if !ok {
		return "", false
	}
	return slotToCombo(slot), true
}
