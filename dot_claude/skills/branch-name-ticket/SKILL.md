---
name: branch-name-ticket
description: Use before committing, pushing, or opening a PR for a feature branch — verifies the branch name carries a Jira ticket key (e.g. GTI-273) and renames it if not. Also use when the user asks to "tag this branch with the ticket", "rename the branch to the ticket", or fix a branch like `docs/foo` or `feat/cleanup` that's missing a key.
---

# Branch name carries the Jira ticket

Every feature branch destined for a PR must include a Jira ticket key (`GTI-NNN`) so reviewers, automation, and `git log` can trace work back to its ticket. This skill checks the current branch and, if the key is missing, finds the right one and renames the branch.

## Branch name format

```
<type>/<TICKET-KEY>-<kebab-summary>
```

- **type**: `feat | fix | chore | docs | refactor | test | ci | build` (same set as the `commit` skill).
- **TICKET-KEY**: uppercase, e.g. `GTI-273`. Match `[A-Z]+-\d+`.
- **kebab-summary**: 2–4 short lowercase tokens describing the work.

Examples from history:

| Good | Notes |
|---|---|
| `feat/GTI-273-WIF-odin-lego` | type + key + summary |
| `feat/GTI-264-add-iqhwan-gtconsole` | classic shape |
| `chore/GTI-251-perms-secret-manager` | non-feat type still works |

Anti-patterns to fix:

| Bad | Why |
|---|---|
| `docs/cloud-run-keyless-auth` | no ticket key |
| `feat/lego-rag-docs` | no ticket key |
| `GTI-259-permission-firebase` | missing `<type>/` prefix |
| `feat/gti-264-cidr-hermes-iris` | lowercase key — normalize to `GTI-264` |

Permanent infra branches (`main`, `develop`, `ci/lint-docs-self-hosted`) are out of scope — never rename them.

## When to use

- About to run `git push -u origin <branch>`, open a PR, or invoke `commit-push-pr`.
- User says "tag this branch with the ticket", "rename branch to the Jira ticket", "this branch needs a ticket".
- You just created a branch like `docs/foo` and realized it has no key.

**Skip** when:
- Branch already matches `<type>/<KEY>-<summary>` with an uppercase key.
- Branch is `main`, `develop`, `master`, or a long-lived release branch.
- User explicitly says the branch should stay as-is (rare — confirm).

## Pre-checks (scripted)

Run the linter - it classifies the current branch and performs the deterministic,
no-Jira-needed normalization (uppercase key, keep slug; handles the case-only rename
that collides on macOS's case-insensitive filesystem):

```bash
~/.claude/skills/branch-name-ticket/branch-name-lint.sh          # add --dry-run to preview without renaming
```

Act on the exit code:

| Exit | `status:` | What to do |
|------|-----------|------------|
| `2`  | `protected` / detached / not a repo | Stop - never rename `main`/`develop`/`master`. |
| `0`  | `ok` or `normalizable` | Done. If it renamed locally, just report before/after. If the branch was pushed, do the remote-rename / open-PR check under **Rename** below. |
| `4`  | `needs-type` | Key present but no valid `<type>/` prefix. Skip to **Pick the type**, then **Rename** to `<type>/<KEY>-<slug>` (the script printed `key` and `slug`). |
| `3`  | `no-key` | No ticket key. Continue to **Find the ticket**. |

The script only ever does a local `git branch -m` (safe, reversible). Finding the
ticket, squeezing the summary, and any **remote** rename stay below - they need
judgment or confirmation.

## Find the ticket

Try these in order. Stop at the first that yields a confident answer.

1. **Tmux window name** — if `$TMUX` is set, run `tmux display-message -p '#W'`. If it matches `[A-Z]+-\d+` (the `rename-tmux-to-ticket` skill sets this), use that key and grab the label too (the part after the space) as the summary.

2. **Recent commits on the branch** — `git log <base>..HEAD --format=%s` where `<base>` is `origin/main` (or `origin/develop` if that's the default). If every commit subject contains the same `[A-Z]+-\d+`, use it.

3. **Jira in-progress assigned to user** — call `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` with JQL like `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`, limit 10. If exactly one is "In Progress", offer it; otherwise present the top 3–5 as a numbered list and ask the user to pick (using `AskUserQuestion` with up to 4 options).
   - Load the MCP tool first via `ToolSearch` if not yet resolved.

4. **Ask the user** — last resort. One short question: "Which ticket key (GTI-NNN) is this branch for?"

## Find the summary

- If the existing branch already has a slug after the `/` (e.g. `docs/cloud-run-keyless-auth`), keep that slug as the summary — don't re-derive.
- Otherwise fetch the ticket summary via `mcp__claude_ai_Atlassian__getJiraIssue` with `fields: ["summary"]` and squeeze it:
  - Lowercase, strip punctuation, em/en dashes.
  - Drop fillers: `the a an of for to on in and with into from by`.
  - Drop ceremony verbs at the start: `create make setup set add build write do enable get give`.
  - Drop generic leading nouns when something specific follows: `request permission access task ticket project`.
  - Keep the first 2–4 *meaningful* tokens, kebab-joined.
  - Hard cap: 30 chars. Drop trailing tokens if over.

(Same rules as `rename-tmux-to-ticket`, just a slightly higher token budget.)

## Pick the type

If the current branch already starts with `<type>/`, reuse it. Otherwise infer:

| Signal | Type |
|---|---|
| Files under `docs/`, `apps/docs/`, `*.md` only | `docs` |
| New Terraform resources, new modules, new app | `feat` |
| Bug fix in existing code (commits with `fix:` etc.) | `fix` |
| CI / pipelines / `.github/`, `bitbucket-pipelines.yml` | `ci` |
| Permissions, deps, version bumps, cleanup | `chore` |
| Pure restructuring, no behavior change | `refactor` |

When in doubt, default to `feat`.

## Rename

Compose `new = <type>/<KEY>-<summary>`.

1. **Local rename** — `git branch -m <new>`. Always safe.

2. **Remote rename if pushed** — check `git config branch.<old>.merge` (or `git ls-remote origin <old>`). If the branch is on origin:
   - **Has an open PR**: STOP. Tell the user the PR will need to be re-opened or its source branch changed manually in Bitbucket/GitHub. Don't auto-delete the remote branch.
   - **No PR yet**: run `git push origin -u <new>` then `git push origin --delete <old>`. Confirm with the user before deleting the remote ref.

3. Show the user the before/after and the commands you ran.

## Examples

| Before | Ticket | Summary | After |
|---|---|---|---|
| `docs/cloud-run-keyless-auth` | GTI-273 | (keep existing slug) | `docs/GTI-273-cloud-run-keyless-auth` |
| `feat/cleanup` | GTI-300 | "Remove unused IAM bindings" | `feat/GTI-300-remove-iam-bindings` |
| `gti-259-permission-firebase` | (already present) | (keep slug) | `chore/GTI-259-permission-firebase` |
| `feat/gti-264-cidr-hermes-iris` | (already present, wrong case) | (keep slug) | `feat/GTI-264-cidr-hermes-iris` |

## Common mistakes

- **Renaming `main`, `develop`, or release branches.** Never. Check the skip list first.
- **Deleting the remote branch while a PR is open against it.** The PR will close or break. Always check for an open PR before `--delete`.
- **Re-deriving the summary when a perfectly good slug already exists.** Wastes a Jira call and changes the slug for no reason. Reuse the existing tail.
- **Leaving the key lowercase** (`gti-264-...`). Normalize to uppercase even when the existing branch had it lowercase.
- **Asking the user before trying tmux/commits/Jira.** The whole point is to find it automatically — only ask when those signals are absent or ambiguous.
- **Forcing a `feat/` prefix on a docs-only or chore-only branch.** Pick the type from the actual content.

## Quick reference

```bash
# Inspect
git branch --show-current
tmux display-message -p '#W'   # may carry the key if rename-tmux-to-ticket was used
git log origin/main..HEAD --format=%s

# Local rename (always safe)
git branch -m <new>

# Remote rename (only if branch was pushed AND no open PR)
git push origin -u <new>
git push origin --delete <old>   # confirm with user first
```
