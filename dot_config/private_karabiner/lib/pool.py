"""F-key pool management for shortcut layer key assignments."""
import json, os

# FKEY_POOL and ALL_MODS are the canonical pool/modifier tables, loaded from
# data/keymap-tables.json (shared with the Go CLI). Their order is significant —
# it defines slot allocation.
from .tables import FKEY_POOL, ALL_MODS

POOL_SIZE = len(FKEY_POOL) * len(ALL_MODS)  # 128


def slot_to_combo(slot):
    """Convert a pool slot index to (fkey, human_mod, goku_mod)."""
    fkey_idx = slot // len(ALL_MODS)
    mod_idx = slot % len(ALL_MODS)
    fkey = FKEY_POOL[fkey_idx]
    human_mod, goku_mod = ALL_MODS[mod_idx]
    return fkey, human_mod, goku_mod


def load_pool(path):
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {}


def save_pool(path, pool_map):
    with open(path, 'w') as f:
        json.dump(pool_map, f, indent=2, sort_keys=True)
        f.write('\n')


def get_or_assign(pool_map, layer_name, key):
    """Return the pool slot for (layer, key), allocating if new."""
    map_key = f"{layer_name}:{key}"
    if map_key in pool_map:
        return pool_map[map_key]
    used = set(pool_map.values())
    for slot in range(POOL_SIZE):
        if slot not in used:
            pool_map[map_key] = slot
            return slot
    raise RuntimeError(f"F-key pool exhausted ({POOL_SIZE} slots)")


def combo_for_key(pool_map, layer_name, key):
    """Return (human_label, goku_to) for a key in a layer."""
    slot = get_or_assign(pool_map, layer_name, key)
    fkey, human_mod, goku_mod = slot_to_combo(slot)
    human = f"{human_mod}{fkey.upper()}"
    goku_to = f":{goku_mod}{fkey}" if goku_mod else f":{fkey}"
    return human, goku_to
