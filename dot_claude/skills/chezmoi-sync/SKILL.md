---
name: chezmoi-sync
description: Use when finishing work on dotfiles, shell config, tmux, nvim, ghostty, or any chezmoi-managed configuration - detects uncommitted chezmoi changes, validates, and pushes
---

# Chezmoi Sync

Detect, validate, and push chezmoi-managed dotfile changes from the current session.

**Source dir:** `~/.local/share/chezmoi`
**Remote:** origin (GitHub dotfiles repo)

## When to Use

- After modifying files in chezmoi source dir (`~/.local/share/chezmoi`)
- After modifying target config files chezmoi manages (e.g., `~/.config/*`, `~/.tmux*`, `~/.zshrc`)
- End of any session that touched dotfiles or shell/editor/terminal config
- When user says "sync", "push dotfiles", or "chezmoi sync"

## When NOT to Use

- Changes are outside chezmoi-managed paths
- User explicitly says they'll commit later
- Working in a project repo, not dotfiles

## Workflow

### 1. Detect Changes

Run in parallel:

```bash
git -C ~/.local/share/chezmoi status
chezmoi diff --no-pager
```

- **git status**: uncommitted changes in chezmoi source
- **chezmoi diff**: target files that diverged from source (edited outside chezmoi)

If BOTH are clean, nothing to sync. Tell the user and stop.

### 2. Reconcile Diverged Targets

If `chezmoi diff` shows target files the user intentionally changed this session:

```bash
chezmoi add <target-path>
```

Only add files that were part of this session's work. Ask the user if unsure.

### 3. Validate

Run in parallel:

```bash
git -C ~/.local/share/chezmoi diff
git -C ~/.local/share/chezmoi status
```

Check for:
- **Secrets**: `.env` files, API keys, tokens, passwords, private keys - STOP and warn
- **Unintended files**: changes outside the scope of this session's work - confirm with user
- **Sensitive chezmoi files**: anything prefixed `private_` deserves extra scrutiny

Present summary:
- Files changed (list them)
- Scope of changes (what was worked on)
- Any warnings

Get user confirmation before proceeding.

### 4. Commit and Push

```bash
# Stage only the relevant files
git -C ~/.local/share/chezmoi add <specific-files>

# Commit - match existing repo style (chore/feat/fix with scope)
git -C ~/.local/share/chezmoi commit -m "scope: description"

# Push
git -C ~/.local/share/chezmoi push
```

**Commit style**: check `git log --oneline -5` in source dir and match. Typical: `chore: update Brewfile`, `tmux: add focus tracking scripts`, `zsh: update aliases`.

### 5. Verify

```bash
git -C ~/.local/share/chezmoi status
```

Confirm working tree is clean and push succeeded.

## Red Flags - STOP

- File contains secrets, API keys, or credentials
- `private_` prefixed files you didn't intentionally modify
- Changes to files outside this session's scope
- Git remote is unreachable

## Do NOT

- Run `chezmoi apply` (this skill syncs source to remote, not source to target)
- Use `git add -A` or `git add .` - stage specific files only
- Push without showing the user what will be pushed
- Commit unrelated changes from other sessions - only sync what was worked on NOW
