---
name: mp-tracker-templates
description: Use when configuring the issue tracker for the mattpocock engineering skills — running /setup-matt-pocock-skills, or writing/editing a repo's docs/agents/issue-tracker.md — in a repo whose remote is Bitbucket, or whose issues live in Jira. Supplies the Bitbucket + Jira seed template that the upstream skill doesn't ship (it only covers GitHub, GitLab, and local markdown). Also use when asked how `/triage`, `/to-tickets`, `/to-spec`, `/qa`, or `/wayfinder` should reach Jira or Bitbucket.
---

# MP tracker templates

`/setup-matt-pocock-skills` ships seed templates for GitHub, GitLab, and local
markdown only. This skill adds the fourth case — **Bitbucket repos, whose issues
live in Jira** — which is the shape most work repos here take.

## When this applies

Check the remote before anything else:

```bash
git remote get-url origin
```

- `bitbucket.org/...` → Bitbucket **Cloud**. Use this skill's template.
- any other Bitbucket host → Bitbucket **Data Center**. Also this template; DC has
  no issue tracker at all, so Jira is the only option.
- `github.com` / `gitlab.com` → not this skill. Use the upstream template.

## What to do

Copy [issue-tracker-bitbucket.md](./issue-tracker-bitbucket.md) to the repo's
`docs/agents/issue-tracker.md`, then fill in the two placeholders:

1. `<PROJECT-KEY>` — the Jira project key for this repo (e.g. `GTC`, `GTI`).
2. **Issue home** — leave as `jira` unless this is a legacy Cloud repo that still
   has its native tracker switched on. Probe it:

   ```bash
   bkt api repositories/<workspace>/<slug> --jq '.has_issues'
   ```

   `bkt repo view --json` does *not* carry that field — it returns a trimmed shape.

Leave the **PRs as a request surface** flag off unless the user asks for external
PRs in the triage queue.

## Why Jira and not Bitbucket Issues

Bitbucket Cloud **removes native Issues on 20 August 2026**, and since April 2026
Issues can't be enabled on repos that weren't already using them. Data Center never
had a tracker. So `bkt issue` is a legacy path with a deadline — the template
documents it, but routes new work to Jira.

## Tool split

- **Issues** → the [`jira`](https://github.com/ankitpokhrel/jira-cli) CLI
  (`brew install jira-cli`), with the Atlassian MCP tools as fallback.
- **PRs, code, pipelines** → [`bkt`](https://github.com/avivsinai/bitbucket-cli)
  (`brew install avivsinai/tap/bitbucket-cli`). `gh` does not work on Bitbucket.

The template carries the verified command tables for both, plus the traps that fail
silently (`jira issue link` argument order, label removal via a leading `-`,
`--no-input` scope, the 100-issue page limit).

## House style still wins

`/to-tickets` decides *decomposition and blocking edges*. It does not own ticket
formatting — if the repo or the user has a ticket-writing convention
(`general:writing-tickets` for GTI/GTech infra, `writing-tickets-fullstack` for app
work, `jira-sdlc`'s six non-negotiables for TBMSIM), that convention owns the title
and body. Follow it and let `/to-tickets` handle the shape of the set.
