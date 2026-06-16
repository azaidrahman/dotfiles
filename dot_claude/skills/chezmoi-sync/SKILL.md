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

### 1. Detect Changes (scripted)

Run the read-only detector - it combines `git status` (source) + `chezmoi diff`
(diverged targets) and scans both diffs for secrets and `private_`/`encrypted_`
files in one pass:

```bash
~/.claude/skills/chezmoi-sync/chezmoi-detect.sh
```

Act on the exit code:

| Exit | Meaning |
|------|---------|
| `2`  | Precondition failed (chezmoi missing / source not a repo) - relay and stop. |
| `0`  | `status: clean` - nothing to sync. Tell the user and stop. |
| `10` | Changes detected, no warnings - read the listings, continue to Step 2. |
| `11` | Changes detected **WITH warnings** (possible secrets / `private_` files). STOP, show the WARNINGS section, and get explicit user sign-off before going further. |

The detector mutates nothing (no `chezmoi add`/`apply`, no git writes). Reconcile
(Step 2) and commit/push (Step 4) stay below, where the judgment and confirmation live.

### 2. Reconcile Diverged Targets

For each target file `chezmoi diff` shows the user changed this session, **first check
how its source is managed** — the reconcile command depends on it:

```bash
basename "$(chezmoi source-path <target-path>)"
```

| Source basename | Source kind | How to reconcile |
|---|---|---|
| plain (e.g. `dot_zshrc`, `config.json`) | static file | `chezmoi add <target-path>` |
| `modify_*` | script that renders the file | **DO NOT `chezmoi add`** — it replaces the script with a static file and loses its logic. Edit the script's rendered output (the heredoc/template body) to include the change. |
| `*.tmpl` (`create_`/`run_` too) | Go-template / script | **DO NOT `chezmoi add`** — hand-edit the template/script so it produces the new output. |

After editing a `modify_`/template source, **verify apply is now a no-op**:

```bash
chezmoi diff --no-pager <target-path>   # expect EMPTY = source renders the live file
chezmoi status                          # expect the entry gone
```

Only reconcile files that were part of this session's work. Ask the user if unsure.

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
- A diverged target whose source is `modify_*`/`*.tmpl` — `chezmoi add` would destroy
  the script/template; edit the source by hand instead (see Step 2)

## Do NOT

- Run `chezmoi apply` (this skill syncs source to remote, not source to target)
- **`chezmoi add` a file whose source is a `modify_` script or `.tmpl` template** — it
  overwrites the script with a static file and silently drops its logic. Check the source
  basename first (Step 2) and hand-edit script/template sources.
- Use `git add -A` or `git add .` - stage specific files only
- Push without showing the user what will be pushed
- Commit unrelated changes from other sessions - only sync what was worked on NOW
