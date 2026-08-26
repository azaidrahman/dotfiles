---
name: mp-tracker-templates
description: Use when configuring the issue tracker for the mattpocock engineering skills — running /setup-matt-pocock-skills, or writing/editing a repo's docs/agents/issue-tracker.md — in a repo whose remote is Bitbucket, or whose issues live in Jira. Supplies the Bitbucket + Jira seed template that the upstream skill doesn't ship (it only covers GitHub, GitLab, and local markdown), with every command written for the twg CLI. Also use when asked how `/triage`, `/to-tickets`, `/to-spec`, `/qa`, or `/wayfinder` should reach Jira or Bitbucket.
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

Fill in one placeholder: `<PROJECT-KEY>` — the Jira project key for this repo
(e.g. `GTC`, `GTI`). Confirm it resolves with `twg jira space get <PROJECT-KEY>`.

Leave the **PRs as a request surface** flag off unless the user asks for external
PRs in the triage queue.

## Why Jira and not Bitbucket Issues

Bitbucket Cloud **removed native Issues on 20 August 2026**. Data Center never had
a tracker. There is no Bitbucket-native issue path left, so Jira is the tracker on
every Bitbucket repo — no probe, no flag.

## Tool split

Both surfaces go through `twg`. `gh` does not work on Bitbucket, and the two
third-party CLIs this skill used to name (`jira-cli` and `bkt`) were dropped.

- **Issues** → `twg jira workitem`, with the Atlassian MCP tools as fallback.
- **PRs, code, pipelines** → `twg bitbucket` (alias `twg bb`), which auto-detects
  the workspace and repo from the git remote.

The template carries the verified command tables for both, plus the traps that fail
silently (`link workitem` wants a link-type **id** and takes the blocker first,
plain `--labels` replaces the whole set, per-workflow status names, and the
envelope that `-o json` writes when stdout is a pipe).

## House style still wins

`/to-tickets` decides *decomposition and blocking edges*. It does not own ticket
formatting — if the repo or the user has a ticket-writing convention
(`general:writing-tickets` for GTI/GTech infra, `writing-tickets-fullstack` for app
work, `jira-sdlc`'s six non-negotiables for TBMSIM), that convention owns the title
and body. Follow it and let `/to-tickets` handle the shape of the set.
