# My Dotfiles

This repository contains my personal dotfiles managed with [chezmoi](https://chezmoi.io/).

## Setup

Currently configured for macOS, with occasional use on Windows when needed. (nvim && wezterm)

## Structure
├── dot_config\
│   ├── aerospace\
│   ├── borders\
│   ├── gh\
│   ├── ghostty\
│   ├── lazygit\
│   ├── nvim\
│   ├── private_karabiner\
│   ├── tmux\
│   ├── wezterm\
│   └── zsh\
└── dot_zshrc

## Usage

To apply these dotfiles to a new system, first install chezmoi:

```bash
# On macOS with Homebrew
brew install chezmoi

# On Windows with winget
winget install --id=twpayne.chezmoi
```

Then init and apply:
```bash
chezmoi init https://github.com/azaidrahman/dotfiles.git
# chezmoi edit ~/[filepath] if you want to configure anything first
chezmoi apply

chezmoi init --apply https://github.com/azaidrahman/dotfiles.git
# if you know what you're doing
```
