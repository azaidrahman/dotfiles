"""Shared lookup tables loaded from data/keymap-tables.json.

This is the single source of truth for the goku key-name map, the F-key pool,
and the modifier-combo list. The Go add-keymap CLI loads the same JSON
(see src/add-keymap/tables.go), so the two stay in sync by construction.
"""
import json
import os

_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'keymap-tables.json')

with open(_PATH) as _f:
    _DATA = json.load(_f)

# Symbol (as typed in YAML) -> goku key name.
GOKU_NAMES = _DATA['goku_names']

# F-keys available to the shortcut-layer pool, in slot-allocation order.
FKEY_POOL = _DATA['fkey_pool']

# (human_prefix, goku_prefix) modifier combos, in slot-allocation order.
ALL_MODS = [tuple(pair) for pair in _DATA['all_mods']]
