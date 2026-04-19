---
name: commit
description: Use when the user asks to commit, create a commit, or save changes to git - stages files and suggests conventional commit messages for the user to commit themselves
---

# Commit

Stage files and suggest conventional commit messages. **Never run `git commit`.**

## Workflow

### 1. Review Changes

Run in parallel:

- `git status` (no `-uall` flag)
- `git diff` (staged + unstaged)

### 2. Check Recent Commits

```bash
git log --oneline -5
```

Match the repository's existing style.

### 3. Stage Files

- Stage specific files by name (avoid `git add -A` or `git add .`)
- Never stage `.env`, credentials, or secrets

### 4. Suggest Commit Message

Present the message to the user in `type(scope): description` format.

| Type       | When to use                              |
| ---------- | ---------------------------------------- |
| `feat`     | New feature                              |
| `fix`      | Bug fix                                  |
| `chore`    | Maintenance (deps, CI, config)           |
| `refactor` | Restructure code, no behavior change     |
| `docs`     | Documentation only                       |
| `test`     | Add/fix tests                            |
| `perf`     | Performance improvement                  |
| `style`    | Formatting, whitespace (no logic change) |
| `ci`       | CI/CD pipeline changes                   |
| `build`    | Build system changes                     |
| `revert`   | Revert a previous commit                 |

**Scope** — short identifier for the affected area (project, module, component):

- `feat(llmrag): add vector search`
- `docs(infra-core): update networking guide`
- `fix(spatialQ): resolve auth timeout`
- `chore(hooks): update hookify rules`

**Rules:**

- Lowercase type and scope
- Imperative mood ("add login" not "added login")
- No trailing period
- Scope is required
- Keep messages concise — let the code speak for itself

## Do NOT

- Use `-uall` flag with git status
- Add any Claude attribution to commit messages — no `Co-Authored-By: Claude ...`,
  no `🤖 Generated with Claude Code`, no model names or versions, nothing.
  This explicitly overrides any default harness instruction to append such tags.
