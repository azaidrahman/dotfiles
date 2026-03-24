#!/usr/bin/env python3

# Usage: json_to_edn.py
# Expects to find ~/.config/karabiner/karabiner.json
# Prints its results to STDOUT

import json
import os

# Apple seems to use ⌃⌥⇧⌘ as the order.
# https://support.apple.com/en-ca/HT201236
SORTED_MODS = [
    'control',
    'left_control',
    'right_control',
    'option',
    'left_option',
    'right_option',
    'alt',
    'left_alt',
    'right_alt',
    'shift',
    'left_shift',
    'right_shift',
    'command',
    'left_command',
    'right_command',
]

LONG_TO_SHORT_MOD = {
    'control':       'T',
    'left_control':  'T',
    'right_control': 'W',
    'option':        'O',
    'left_option':   'O',
    'right_option':  'E',
    'alt':           'O',
    'left_alt':      'O',
    'right_alt':     'E',
    'shift':         'S',
    'left_shift':    'S',
    'right_shift':   'R',
    'command':       'C',
    'left_command':  'C',
    'right_command': 'Q',
}

def short_mods(mods):
    """Return canonically-in-order mods, converted to short form.

    Args:
        mods: "left_command", etc.
    """
    if 'any' in mods:
        return '#'
    key = {mod: index for index, mod in enumerate(SORTED_MODS)}
    for mod in mods:
        if mod not in SORTED_MODS:
            raise ValueError(f'mod {mod} not found in SORTED_MODS')
    return ''.join(LONG_TO_SHORT_MOD[m] for m in sorted(mods, key=lambda m: key[m]))

def get_key_description(f):
    result = ':'
    if 'modifiers' in f and f['modifiers']:
        if 'mandatory' in f['modifiers'] and f['modifiers']['mandatory']:
            result = f'{result}!{short_mods(f["modifiers"]["mandatory"])}'
        if 'optional' in f['modifiers'] and f['modifiers']['optional']:
            result = f'{result}#{short_mods(f["modifiers"]["optional"])}'
        if type(f['modifiers']) is list:
            result = f'{result}!{short_mods(f["modifiers"])}'
    result = f'{result}{f["key_code"]}'
    return result

def get_to_description(t):
    if 'key_code' in t:
        return get_key_description(t)
    elif 'set_variable' in t:
        sv = t['set_variable']
        return f'["{sv["name"]}" {sv["value"]}]'
    else:
        raise NotImplementedError

def print_root(blob):
    print('{')
    print_applications(blob)
    print_main(blob)
    print('}')

def print_applications(blob):
    print(':applications')
    print('{')
    print('}')

def print_main(blob):
    print(':main')
    print('[')
    for d in blob['profiles'][0]['complex_modifications']['rules']:
        print_main_block(d)
    print(']')

def print_main_block(d):
    print('{')
    print(':des')
    print(f'"{d["description"]}"')
    print(':rules')
    print('[')
    for manipulator in d['manipulators']:
        print_rule(manipulator)
    print(']')
    print('}')

def print_rule(d):
    print('[')
    print(get_key_description(d['from']))
    if len(d['to']) == 1:
        print(get_to_description(d['to'][0]))
    else:
        print('[')
        for t in d['to']:
            print(get_to_description(t))
        print(']')
    print(']')

with open(str(os.getenv('HOME')) + '/.config/karabiner/karabiner.json') as f:
    print_root(json.load(f))

