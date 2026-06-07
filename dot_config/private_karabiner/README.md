# Karabiner Configuration

Goku-based Karabiner-Elements config managed by chezmoi.

## Directory Structure

```
├── karabiner.base.edn     # Main config (edit this)
├── layers.edn             # Layer rules (auto-generated sections)
├── karabiner.edn          # Generated — don't edit directly
├── private_karabiner.json # Compiled output — don't edit
├── config/                # YAML definitions (edit these)
│   ├── help-text.yaml     # App launcher + workspace shortcuts
│   ├── shortcuts.yaml     # Shortcut layers (l1/l2/l3)
│   └── hyperkeys.yaml     # Hyper navigation reference
├── lib/                   # Shared Python modules
│   ├── parser.py          # YAML parsing, QWERTY sort, help text
│   ├── pool.py            # F-key pool management
│   └── generator.py       # EDN rule generation
├── scripts/
│   ├── generate.py        # Main generator entry point
│   ├── show-time.sh       # Time HUD launcher
│   └── time-hud           # Compiled time HUD binary
├── src/                   # Swift sources (compile when needed)
│   ├── help-hud.swift
│   └── time-hud.swift
└── data/
    └── fkey-pool.json     # Persistent F-key slot assignments
```

## Prerequisites

- [uv](https://docs.astral.sh/uv/) (Python package runner — handles PyYAML automatically)
- [goku](https://github.com/yqrashawn/GokuRakuJoudo) (EDN → Karabiner JSON compiler)
- [chezmoi](https://chezmoi.io/) (dotfile manager)

## Building

```bash
./build.sh           # merge layers + generate from YAML + goku
chezmoi apply        # deploy to ~/.config/karabiner/
goku                 # recompile (reads from deployed path)
```

`uv run` handles Python dependencies (PyYAML) automatically — no venv or pip needed.

**Important:** goku reads from `~/.config/karabiner/karabiner.edn`, not the chezmoi source. Always `chezmoi apply` before running `goku` separately.

## Layers

### App Launcher (Right Option)

Hold Right Option to activate. Press keys to launch apps.

**Edit:** `config/help-text.yaml` under `app:`

```yaml
app:
  # key | label | app name
  - w | WA | Whatsapp
  - W | messages | Messages    # uppercase = shift+key
  - c | switch | !Cgrave_accent_and_tilde  # !Command = goku key combo
```

### Workspace (Left Option)

Hold Left Option + key for aerospace window management.

**Edit:** `config/help-text.yaml` under `workspace:` and `workspace-shift:`

```yaml
workspace:
  # key | label | aerospace command
  - h | ← | focus --boundaries-action wrap-around-the-workspace left

workspace-shift:
  # key | label | aerospace command (opt+shift+key)
  - h | mv← | move left
```

### Shortcut Layers (l1/l2/l3)

Triggered by modifier + Right Option:
- **l1:** Shift + Right Option
- **l2:** Ctrl + Right Option
- **l3:** Cmd + Right Option

**Edit:** `config/shortcuts.yaml`

```yaml
l1:
  - o | 1p | 1Password quick access
  - p | dot | chezmoi dotfiles
```

Keys are auto-assigned to F-key combos (persisted in `data/fkey-pool.json`). Adding entries won't reshuffle existing assignments.

### Hyper Navigation (CapsLock)

CapsLock held = Hyper (right modifiers). Provides vim-style navigation.

**Edit:** `config/hyperkeys.yaml` — **declarative**: generates both EDN rules and help overlay.

```yaml
hyper:
  h:
    -: left_arrow                   # ←
    shift: "!TStab"                 # prevTab
    cmd: "!Sleft_arrow"             # sel
    opt: "!Oleft_arrow"             # word
    opt+cmd: "!OSleft_arrow"        # selWord
```

- `-` is the base hyper+key action
- Other keys are extra modifiers on top of hyper
- The `# comment` becomes the help overlay label
- Actions can be sequences: `["!Sdown_arrow", "!Sdown_arrow", "!Sdown_arrow"]`
- `misc` section defines help-only entries (rules stay in `karabiner.base.edn`)

## Interactive: `add-keymap`

Instead of hand-editing YAML, run the wizard to add a keymap to any layer:

```bash
./scripts/executable_add-keymap     # or, once deployed: ~/.config/karabiner/scripts/add-keymap
```

It prompts for layer → key (with validation + collision check) → target, writes the
right YAML, runs `./build.sh`, reports the assigned key/F-key combo, and offers to
`chezmoi apply && goku`.

For shortcut layers (l1/l2/l3) you can pick an auto-assigned **F-key combo** (to bind
in Alfred/Keyboard Maestro) or a **direct action** (`open:App` or a raw goku combo).

**Rebuild the binary after changing Go source** (`src/add-keymap/`):

```bash
./src/add-keymap/build.sh
```

Requires Go (build-time only; the committed binary needs nothing at runtime). The
wizard resolves the chezmoi *source* dir via `chezmoi source-path`; set
`ADDKEYMAP_SOURCE=/path/to/dir` to override (used for testing).

## Help Overlays

Press `/` while in any layer to show its help overlay. Release to dismiss.

| Layer     | Trigger                     |
|-----------|-----------------------------|
| App       | Right Option, then `/`      |
| L1        | Shift+RightOpt, then `/`    |
| L2        | Ctrl+RightOpt, then `/`     |
| L3        | Cmd+RightOpt, then `/`      |
| Workspace | Left Option + `/`           |
| Hyper     | CapsLock + `/`              |

Comments in YAML files create `\n`-separated sections in the help overlay.

## Adding a New Layer

1. Add section to `config/shortcuts.yaml` (e.g., `l4:`)
2. Add layer definition to `lib/generator.py` `LAYERS` dict
3. Add trigger rule to `karabiner.base.edn` (modifier + right_option)
4. Add `/` help rule to `karabiner.base.edn`
5. Run `./build.sh`
