# Chezmoi Dotfiles

## Active work context

The user uses a `ctx` system to associate a work context (ticket, project, or topic) with a local directory.

- **`~/.config/active-ctx`** — plain text file containing the current context name (e.g. `GTI-197` or `chezmoi-refactor`)
- **`~/ctx/<name>/`** — the context directory; may contain HTML research artifacts, notes, data, or anything else
- **`$CTX_DIR`** — env var set in every shell pointing to the active context directory

When the user asks "look at my research" or "check my context", read `~/.config/active-ctx` to find the active context name, then look in `~/ctx/<name>/`. When saving HTML artifacts for the user, write them to `$CTX_DIR` (or `~/ctx/<name>/` if `$CTX_DIR` isn't set).

## Shell functions

- `ctx <name>` — switch to a context (creates `~/ctx/<name>/` if needed, sets `$CTX_DIR`)
- `ctx` — show active context
- `ctx ls` — list all contexts
- `ctx cd` — cd into `$CTX_DIR`
