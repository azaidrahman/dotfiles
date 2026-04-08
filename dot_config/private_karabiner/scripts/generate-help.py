#!/usr/bin/env python3
"""Generate help text, app-launch rules, and shortcut layer rules from YAML configs.

Reads:
  scripts/help-text.yaml     -- app-launch shortcuts
  scripts/shortcuts.yaml     -- shortcut layer definitions
  scripts/fkey-pool.json     -- persisted F-key assignments (auto-managed)

Writes:
  karabiner.edn              -- replaces content between BEGIN/END markers
  scripts/fkey-pool.json     -- updated with any new assignments
"""
import re, sys, os, json

QWERTY = list("qwertyuiop[]\\asdfghjkl;'zxcvbnm,./")

# -- F-key pool ---------------------------------------------------------------
# 8 F-keys x 16 modifier combos = 128 unique slots.

FKEY_POOL = ['f13', 'f14', 'f15', 'f16', 'f17', 'f18', 'f19', 'f20']

ALL_MODS = [
    ('',              ''),
    ('ctrl+',         '!T'),
    ('cmd+',          '!C'),
    ('opt+',          '!O'),
    ('ctrl+cmd+',     '!CT'),
    ('ctrl+opt+',     '!TO'),
    ('cmd+opt+',      '!CO'),
    ('ctrl+cmd+opt+', '!CTO'),
    ('shift+',              '!S'),
    ('ctrl+shift+',         '!TS'),
    ('cmd+shift+',          '!CS'),
    ('opt+shift+',          '!OS'),
    ('ctrl+cmd+shift+',     '!CTS'),
    ('ctrl+opt+shift+',     '!TOS'),
    ('cmd+opt+shift+',      '!COS'),
    ('ctrl+cmd+opt+shift+', '!CTOS'),
]

POOL_SIZE = len(FKEY_POOL) * len(ALL_MODS)  # 128


def slot_to_combo(slot):
    """Convert a pool slot index to (fkey, human_mod, goku_mod)."""
    fkey_idx = slot // len(ALL_MODS)
    mod_idx = slot % len(ALL_MODS)
    fkey = FKEY_POOL[fkey_idx]
    human_mod, goku_mod = ALL_MODS[mod_idx]
    return fkey, human_mod, goku_mod


# -- Key names -----------------------------------------------------------------

GOKU_NAMES = {
    '-': 'hyphen', '=': 'equal_sign', '[': 'open_bracket', ']': 'close_bracket',
    ';': 'semicolon', "'": 'quote', ',': 'comma', '.': 'period',
    '/': 'slash', '\\': 'backslash', '`': 'grave_accent_and_tilde',
    'space': 'spacebar',
}

# layer -> (from_modifier, condition_var, description)
LAYERS = {
    'l1': ('!S', 'shortcut-l1', 'Shortcut Layer 1 (Shift+RightOpt)'),
    'l2': ('!T', 'shortcut-l2', 'Shortcut Layer 2 (Ctrl+RightOpt)'),
    'l3': ('!C', 'shortcut-l3', 'Shortcut Layer 3 (Cmd+RightOpt)'),
}


# -- Pool persistence ---------------------------------------------------------

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


# -- Helpers -------------------------------------------------------------------

def qwerty_pos(key):
    low = key.lower()
    pos = QWERTY.index(low) if low in QWERTY else 999
    return (pos, 0 if key.islower() or not key.isalpha() else 1)


def parse_yaml(path):
    sections = {}
    current = None
    with open(path) as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            if re.match(r'^[a-z][\w-]*:\s*$', stripped):
                current = stripped.rstrip(': ')
                sections[current] = []
            elif current and stripped.startswith('- '):
                val = stripped[2:].strip()
                if not val.startswith('#'):
                    sections[current].append(val)
    return sections


def parse_entry(entry):
    """Parse 'key | label | extra' or 'key | label'."""
    parts = [p.strip() for p in entry.split('|')]
    key = parts[0]
    label = parts[1] if len(parts) > 1 else key
    extra = parts[2] if len(parts) > 2 else None
    return key, label, extra


def help_text(entries):
    items = []
    for entry in entries:
        key, label, _ = parse_entry(entry)
        items.append((key, f"{key}:{label}"))
    items.sort(key=lambda x: qwerty_pos(x[0]))
    return ', '.join(t for _, t in items)


# -- App-launch rules ---------------------------------------------------------

def make_rule(key, label, app):
    is_shifted = key.isupper() and key.isalpha()
    from_key = f":!S{key.lower()}" if is_shifted else f":{key}"
    if app and app.startswith('!'):
        to_part = f":{app}"
    elif app:
        to_part = f'[:open "{app}"]'
    else:
        to_part = f'[:open "{label}"]'
    inner = f"[{from_key} {to_part}"
    return f"    {inner:<38s}:app-launch]"


def extract_edn_keys(existing_block):
    active = {}
    commented = {}
    if not existing_block:
        return active, commented
    for line in existing_block.split('\n'):
        stripped = line.strip()
        m = re.match(r'\[:(!S)?([a-z])\s', stripped)
        if m:
            key = m.group(2).upper() if m.group(1) == '!S' else m.group(2)
            active[key] = stripped
            continue
        m = re.match(r';+\s*\[:(!S)?([a-z])\s', stripped)
        if m:
            key = m.group(2).upper() if m.group(1) == '!S' else m.group(2)
            commented[key] = stripped.lstrip('; ')
    return active, commented


def generate_app_rules(entries, existing_block):
    warnings = []
    new_keys = set()
    shifted, unshifted = [], []

    for entry in entries:
        key, label, app = parse_entry(entry)
        new_keys.add(key)
        rule = make_rule(key, label, app)
        if key.isupper() and key.isalpha():
            shifted.append((key, rule))
        else:
            unshifted.append((key, rule))

    shifted.sort(key=lambda x: qwerty_pos(x[0]))
    unshifted.sort(key=lambda x: qwerty_pos(x[0]))

    active, commented = extract_edn_keys(existing_block)
    removed_shifted, removed_unshifted = [], []

    for key, rule_line in active.items():
        if key not in new_keys:
            warnings.append(f"  COMMENTING OUT: '{key}' active in EDN but missing from YAML -> {rule_line}")
            entry = (key, f"    ; {rule_line}")
            if key.isupper() and key.isalpha():
                removed_shifted.append(entry)
            else:
                removed_unshifted.append(entry)

    for key, rule_line in commented.items():
        if key not in new_keys:
            entry = (key, f"    ; {rule_line}")
            if key.isupper() and key.isalpha():
                removed_shifted.append(entry)
            else:
                removed_unshifted.append(entry)

    all_edn_keys = set(active) | set(commented)
    for key in sorted(new_keys - all_edn_keys, key=qwerty_pos):
        warnings.append(f"  NEW RULE: '{key}' in YAML but not yet in EDN -> will be added")

    removed_shifted.sort(key=lambda x: qwerty_pos(x[0]))
    removed_unshifted.sort(key=lambda x: qwerty_pos(x[0]))

    lines = ['    ;; Shifted shortcuts']
    lines += [r for _, r in shifted]
    lines += [r for _, r in removed_shifted]
    lines += ['']
    lines += ['    ;; Unshifted shortcuts']
    lines += [r for _, r in unshifted]
    lines += [r for _, r in removed_unshifted]
    return '\n'.join(lines), warnings


# -- Shortcut layer rules -----------------------------------------------------

def generate_layer(pool_map, layer_name, entries):
    """Generate a complete Goku rule block for a shortcut layer."""
    from_mod, condition, des = LAYERS[layer_name]
    n = layer_name[-1]

    # Parse entries and resolve pool slots
    parsed = []
    for entry in entries:
        key, label, _ = parse_entry(entry)
        slot = get_or_assign(pool_map, layer_name, key)
        parsed.append((slot, key, label))
    parsed.sort()  # sort by slot -> groups by F-key naturally

    # Build rule lines with F-key group headers
    rule_lines = []
    current_fkey = None
    for slot, key, label in parsed:
        fkey, human_mod, goku_mod = slot_to_combo(slot)

        if fkey != current_fkey:
            if rule_lines:
                rule_lines.append('')
            rule_lines.append(f'    ;; --- {fkey.upper()} ---')
            current_fkey = fkey

        gk = GOKU_NAMES.get(key, key)
        human = f"{human_mod}{fkey.upper()}"
        goku_to = f":{goku_mod}{fkey}" if goku_mod else f":{fkey}"
        from_str = f":{from_mod}{gk}"

        if len(gk) > 1:
            rule = f"    [{from_str:<28s}{goku_to:<15s}:{condition}]   ;; {key} -> {human} ({label})"
        else:
            rule = f"    [{from_str:<10s}{goku_to:<15s}:{condition}]   ;; {key} -> {human} ({label})"
        rule_lines.append(rule)

    # Assemble block
    header = f';; BEGIN SHORTCUT-LAYER-{n} (auto-generated from scripts/shortcuts.yaml)'
    footer = f';; END SHORTCUT-LAYER-{n}'

    if not rule_lines:
        return f'{header}\n{footer}'

    lines = [header]
    lines.append(f'  {{:des "{des}"')
    lines.append('   :rules')
    lines.append(f'   [{rule_lines[0].lstrip()}')
    for rl in rule_lines[1:]:
        lines.append(rl)
    lines.append('   ]}')
    lines.append(footer)
    return '\n'.join(lines)


def print_mapping(pool_map, layer_name, entries):
    """Print a human-readable mapping table for a layer."""
    _, _, des = LAYERS[layer_name]
    parsed = []
    for entry in entries:
        key, label, desc = parse_entry(entry)
        slot = pool_map.get(f"{layer_name}:{key}")
        if slot is None:
            continue
        fkey, human_mod, _ = slot_to_combo(slot)
        human = f"{human_mod}{fkey.upper()}"
        parsed.append((slot, key, human, label, desc or ''))
    parsed.sort()

    if not parsed:
        return

    print(f"\n  {des}:")
    for _, key, human, label, desc in parsed:
        desc_str = f'  ({desc})' if desc else ''
        print(f"    {key:<6s} -> {human:<24s} {label}{desc_str}")


# -- Workspace rules (aerospace CLI) ------------------------------------------

def generate_workspace_rules(ws_entries, ws_shift_entries):
    """Generate workspace rules: opt+key -> aerospace CLI via :aero template."""
    lines = []

    if ws_entries:
        lines.append('    ;; opt+key')
        for entry in ws_entries:
            key, label, command = parse_entry(entry)
            gk = GOKU_NAMES.get(key, key)
            from_str = f":!O{gk}"
            to_str = f'[:aero "{command}"]'
            if len(gk) > 1:
                lines.append(f'    [{from_str:<28s}{to_str}]  ;; {label}')
            else:
                lines.append(f'    [{from_str:<10s}{to_str}]  ;; {label}')

    if ws_shift_entries:
        if lines:
            lines.append('')
        lines.append('    ;; opt+shift+key')
        for entry in ws_shift_entries:
            key, label, command = parse_entry(entry)
            gk = GOKU_NAMES.get(key, key)
            from_str = f":!OS{gk}"
            to_str = f'[:aero "{command}"]'
            if len(gk) > 1:
                lines.append(f'    [{from_str:<28s}{to_str}]  ;; {label}')
            else:
                lines.append(f'    [{from_str:<10s}{to_str}]  ;; {label}')

    return '\n'.join(lines)


# -- Main ---------------------------------------------------------------------

dir_path = sys.argv[1]
yaml_path = os.path.join(dir_path, 'scripts', 'help-text.yaml')
shortcuts_path = os.path.join(dir_path, 'scripts', 'shortcuts.yaml')
pool_path = os.path.join(dir_path, 'scripts', 'fkey-pool.json')
edn_path = os.path.join(dir_path, 'karabiner.edn')

app_sections = parse_yaml(yaml_path)
shortcut_sections = parse_yaml(shortcuts_path) if os.path.exists(shortcuts_path) else {}
pool_map = load_pool(pool_path)

edn = open(edn_path).read()

# -- Help text -----------------------------------------------------------------

app_t = help_text(app_sections.get('app', []))

# Workspace help text (merge unshifted + shifted by key)
ws_entries = app_sections.get('workspace', [])
ws_shift_entries = app_sections.get('workspace-shift', [])

ws_labels = {}  # key -> unshifted label
for entry in ws_entries:
    key, label, _ = parse_entry(entry)
    ws_labels[key] = label

ws_shift_labels = {}  # key -> shifted label
for entry in ws_shift_entries:
    key, label, _ = parse_entry(entry)
    ws_shift_labels[key] = label

# Merge: keys from both sections, sorted by QWERTY position
all_ws_keys = sorted(set(ws_labels) | set(ws_shift_labels), key=qwerty_pos)
ws_items = []
for key in all_ws_keys:
    base = ws_labels.get(key)
    shift = ws_shift_labels.get(key)
    if base and shift:
        ws_items.append(f"{key}:{base}/{shift}")
    elif base:
        ws_items.append(f"{key}:{base}")
    elif shift:
        ws_items.append(f"⇧{key}:{shift}")
ws_t = ', '.join(ws_items)

layer_help_lines = []
for ln in sorted(LAYERS.keys()):
    entries = shortcut_sections.get(ln, [])
    t = help_text(entries) if entries else ''
    n = ln[-1]
    layer_help_lines.append(
        f'       :show-{ln}-help {{:noti {{:id "org.pqrs.notificaion_message_layer{n}"\n'
        f'                             :text "{t}"}}}}\n'
        f'       :clear-{ln}-help {{:noti {{:id "org.pqrs.notificaion_message_layer{n}"\n'
        f'                              :text ""}}}}'
    )

help_block = (
    ';; BEGIN HELP-TEXT (auto-generated from scripts/help-text.yaml)\n'
    ' :tos {:show-app-help {:noti {:id "org.pqrs.notificaion_message_global_shortcut"\n'
    '                              :text "' + app_t + '"}}\n'
    '       :clear-app-help {:noti {:id "org.pqrs.notificaion_message_global_shortcut"\n'
    '                               :text ""}}\n'
    '       :show-ws-help {:noti {:id "org.pqrs.notificaion_message_workspace"\n'
    '                             :text "' + ws_t + '"}}\n'
    '       :clear-ws-help {:noti {:id "org.pqrs.notificaion_message_workspace"\n'
    '                              :text ""}}\n'
    + '\n'.join(layer_help_lines) + '\n'
    '       :show-hyper-help {:noti {:id "org.pqrs.notificaion_message_hyper"\n'
    '                                :text "h:← j:↓ k:↑ l:→ | u:home p:end | x:⌫ ⇧x:⌦ | ⇧h/l:tabs ⇧j/k:apps | ⌘:select ⌥:word | f:expose spc:lang"}}\n'
    '       :clear-hyper-help {:noti {:id "org.pqrs.notificaion_message_hyper"\n'
    '                                 :text ""}}}\n'
    ';; END HELP-TEXT'
)

edn = re.sub(r';; BEGIN HELP-TEXT.*?;; END HELP-TEXT', help_block, edn, flags=re.DOTALL)

# -- App rules -----------------------------------------------------------------

existing = ''
m = re.search(r';; BEGIN APP-RULES.*?;; END APP-RULES', edn, re.DOTALL)
if m:
    existing = m.group(0)

rules, warnings = generate_app_rules(app_sections.get('app', []), existing)

rules_block = (
    ';; BEGIN APP-RULES (auto-generated from scripts/help-text.yaml)\n'
    + rules + '\n'
    ';; END APP-RULES'
)

edn = re.sub(r';; BEGIN APP-RULES.*?;; END APP-RULES', rules_block, edn, flags=re.DOTALL)

# -- Shortcut layers -----------------------------------------------------------

for ln in sorted(LAYERS.keys()):
    n = ln[-1]
    entries = shortcut_sections.get(ln, [])
    block = generate_layer(pool_map, ln, entries)
    pattern = rf';; BEGIN SHORTCUT-LAYER-{n}.*?;; END SHORTCUT-LAYER-{n}'
    edn = re.sub(pattern, block, edn, flags=re.DOTALL)

# -- Workspace rules -----------------------------------------------------------

ws_rules = generate_workspace_rules(ws_entries, ws_shift_entries)
ws_block_header = ';; BEGIN WORKSPACE-RULES (auto-generated from scripts/help-text.yaml)'
ws_block_footer = ';; END WORKSPACE-RULES'

if ws_rules:
    ws_block = (
        ws_block_header + '\n'
        '  {:des "Workspace shortcuts (Left Option)"\n'
        '   :rules\n'
        '   [' + ws_rules.lstrip() + '\n'
        '   ]}\n'
        + ws_block_footer
    )
else:
    ws_block = ws_block_header + '\n' + ws_block_footer

edn = re.sub(r';; BEGIN WORKSPACE-RULES.*?;; END WORKSPACE-RULES', ws_block, edn, flags=re.DOTALL)

# -- Write ---------------------------------------------------------------------

open(edn_path, 'w').write(edn)
save_pool(pool_path, pool_map)

# -- Summary -------------------------------------------------------------------

if warnings:
    print("\n\033[33m! YAML <-> EDN out of sync:\033[0m")
    for w in warnings:
        print(w)
    print()

print(f"  app: {app_t}")
print(f"  rules: {len(app_sections.get('app', []))} active")
print(f"  pool: {len(pool_map)}/{POOL_SIZE} slots used")

print(f"  ws:  {ws_t}")

for ln in sorted(LAYERS.keys()):
    entries = shortcut_sections.get(ln, [])
    t = help_text(entries) if entries else '(empty)'
    print(f"  {ln}:  {t}")
    print_mapping(pool_map, ln, entries)
