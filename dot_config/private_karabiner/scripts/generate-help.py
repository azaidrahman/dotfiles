#!/usr/bin/env python3
"""Generate help text and app-launch rules from help-text.yaml into karabiner.edn."""
import re, sys, os

QWERTY = list("qwertyuiop[]\\asdfghjkl;'zxcvbnm,./")

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
            if re.match(r'^[a-z]\w*:\s*$', stripped):
                current = stripped.rstrip(': ')
                sections[current] = []
            elif current and stripped.startswith('- '):
                val = stripped[2:].strip()
                if not val.startswith('#'):
                    sections[current].append(val)
    return sections


def parse_entry(entry):
    """Parse 'key | label | app' or 'key | label'."""
    parts = [p.strip() for p in entry.split('|')]
    key = parts[0]
    label = parts[1] if len(parts) > 1 else key
    app = parts[2] if len(parts) > 2 else None
    return key, label, app


def help_text(entries):
    items = []
    for entry in entries:
        key, label, _ = parse_entry(entry)
        items.append((key, f"{key}:{label}"))
    items.sort(key=lambda x: qwerty_pos(x[0]))
    return ', '.join(t for _, t in items)


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
    """Extract key -> rule-line mappings from active rules between markers."""
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


def generate_rules(entries, existing_block):
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

    # Detect out-of-sync: active EDN rules not in YAML → will be commented out
    active, commented = extract_edn_keys(existing_block)
    removed_shifted, removed_unshifted = [], []

    for key, rule_line in active.items():
        if key not in new_keys:
            warnings.append(f"  COMMENTING OUT: '{key}' active in EDN but missing from YAML → {rule_line}")
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

    # Detect out-of-sync: YAML entries not in EDN (new additions)
    all_edn_keys = set(active) | set(commented)
    for key in sorted(new_keys - all_edn_keys, key=qwerty_pos):
        warnings.append(f"  NEW RULE: '{key}' in YAML but not yet in EDN → will be added")

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


# ── Main ──────────────────────────────────────────────────────────────────
dir_path = sys.argv[1]
yaml_path = os.path.join(dir_path, 'scripts', 'help-text.yaml')
edn_path = os.path.join(dir_path, 'karabiner.edn')

sections = parse_yaml(yaml_path)
edn = open(edn_path).read()

# ── Help text ─────────────────────────────────────────────────────────────
app_t = help_text(sections.get('app', []))
l1_t  = help_text(sections.get('l1', []))
l2_t  = help_text(sections.get('l2', []))

help_block = (
    ';; BEGIN HELP-TEXT (auto-generated from scripts/help-text.yaml)\n'
    ' :tos {:show-app-help {:noti {:id "org.pqrs.notificaion_message_global_shortcut"\n'
    '                              :text "' + app_t + '"}}\n'
    '       :clear-app-help {:noti {:id "org.pqrs.notificaion_message_global_shortcut"\n'
    '                               :text ""}}\n'
    '       :show-l1-help {:noti {:id "org.pqrs.notificaion_message_layer1"\n'
    '                             :text "' + l1_t + '"}}\n'
    '       :clear-l1-help {:noti {:id "org.pqrs.notificaion_message_layer1"\n'
    '                              :text ""}}\n'
    '       :show-l2-help {:noti {:id "org.pqrs.notificaion_message_layer2"\n'
    '                             :text "' + l2_t + '"}}\n'
    '       :clear-l2-help {:noti {:id "org.pqrs.notificaion_message_layer2"\n'
    '                              :text ""}}\n'
    ' }\n'
    ';; END HELP-TEXT'
)

edn = re.sub(r';; BEGIN HELP-TEXT.*?;; END HELP-TEXT', help_block, edn, flags=re.DOTALL)

# ── App rules ─────────────────────────────────────────────────────────────
existing = ''
m = re.search(r';; BEGIN APP-RULES.*?;; END APP-RULES', edn, re.DOTALL)
if m:
    existing = m.group(0)

rules, warnings = generate_rules(sections.get('app', []), existing)

rules_block = (
    ';; BEGIN APP-RULES (auto-generated from scripts/help-text.yaml)\n'
    + rules + '\n'
    ';; END APP-RULES'
)

edn = re.sub(r';; BEGIN APP-RULES.*?;; END APP-RULES', rules_block, edn, flags=re.DOTALL)

open(edn_path, 'w').write(edn)

if warnings:
    print("\n\033[33m⚠ YAML ↔ EDN out of sync:\033[0m")
    for w in warnings:
        print(w)
    print()

print(f"  app: {app_t}")
print(f"  l1:  {l1_t}")
print(f"  l2:  {l2_t}")
print(f"  rules: {len(sections.get('app', []))} active")
