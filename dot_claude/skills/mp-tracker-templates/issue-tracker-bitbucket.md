# Issue tracker: Bitbucket

This repo lives on Bitbucket. Two surfaces, two tools:

- **Issues / PRDs → Jira**, via the [`jira`](https://github.com/ankitpokhrel/jira-cli) CLI (Atlassian MCP tools as fallback). Bitbucket's own issue tracker is end-of-life (see below).
- **Pull requests, code, pipelines → the [`bkt`](https://github.com/avivsinai/bitbucket-cli) CLI.** `gh` does not work against Bitbucket.

```bash
bkt --version && bkt auth status
```

If `bkt` isn't installed: `brew install avivsinai/tap/bitbucket-cli` (or `go install github.com/avivsinai/bitbucket-cli/cmd/bkt@latest`). If it's unauthenticated or lacks a capability, fall back to a connected Bitbucket MCP server, then to `bkt api` raw requests. Say you're falling back and why.

## Why Jira and not Bitbucket Issues

**Bitbucket Cloud removes native Issues on 20 August 2026**, and since **April 2026** Issues can no longer be enabled on repos that weren't already using them. Bitbucket **Data Center / Server never had an issue tracker** at all. So on any Bitbucket repo, Jira is the tracker unless this specific repo is a Cloud repo that already had Issues switched on before the April cutoff.

**Issue home: `jira`.** _(Set to `bitbucket-native` only for a legacy Cloud repo that still has its tracker on — and expect it to break after 20 Aug 2026.)_

Probe which situation you're in:

```bash
bkt api repositories/<workspace>/<slug> --jq '.has_issues'    # false → Jira, no question
bkt issue list --json                                          # 410 Gone → tracker already removed
```

`bkt repo view --json` does **not** carry `has_issues` — it returns a trimmed shape (`workspace`, `slug`, `name`, `uuid`, `web_url`, `clone_urls`). Use `bkt api` for that field.

## Issue operations (Jira)

**Jira project key for this repo: `<PROJECT-KEY>`.**

**Prefer the [`jira`](https://github.com/ankitpokhrel/jira-cli) CLI** (`ankitpokhrel/jira-cli`). Same posture as `bkt` for Bitbucket: cheaper per call, scriptable, and `--raw` pipes into `jq`. Probe it first; if the probe fails, fall through to MCP and say so.

```bash
jira version && jira me
```

If it isn't installed: `brew install jira-cli` (homebrew-core), or `docker run -it --rm ghcr.io/ankitpokhrel/jira-cli:latest`. First-time setup is `jira init` — pick Cloud or Local, then supply site and email. It writes `~/.config/.jira/.config.yml` with a **default project**, so `-p<PROJECT-KEY>` (a global flag) is only needed to target a different one.

| Operation | Command |
| --- | --- |
| Create an issue | `jira issue create -tTask -s"<summary>" -b"<body>" -l<label> -yHigh --no-input` |
| Create under an epic | `jira issue create -tStory -P<EPIC-KEY> -s"..." --no-input` |
| Read an issue | `jira issue view <KEY> --comments 20` |
| Query by field | `jira issue list -l needs-triage -s"To Do" -a$(jira me) --plain --no-headers` |
| Query by JQL | `jira issue list -q '<JQL>' --raw` |
| Comment | `jira issue comment add <KEY> "<text>"` — or pipe the body on stdin |
| Add a label | `jira issue edit <KEY> --label <name> --no-input` |
| Remove a label | `jira issue edit <KEY> --label -<name> --no-input` |
| Transition | `jira issue move <KEY> "<Status Name>" [--comment "..."] [-R <resolution>]` |
| Assign / unassign | `jira issue assign <KEY> $(jira me)` / `jira issue assign <KEY> x` |
| Link a blocker | `jira issue link <BLOCKER> <BLOCKED> Blocks` |
| Epics | `jira epic list`, `jira epic create -n"<name>" -s"<summary>"`, `jira epic add <EPIC-KEY> <KEY>...` |

Five traps, all of them things that fail quietly:

- **A leading `-` on the value removes it** — `--label -needs-triage` removes, `--label needs-triage` appends. Same convention for `--component` and `--fix-version`. There is no `--remove-label`.
- **`--no-input` only suppresses prompts for *non-required* fields.** Required ones (type, summary) must still come from flags, or the command blocks on an interactive prompt and hangs a non-interactive session.
- **`jira issue link` is inward-then-outward**: `jira issue link A B Blocks` means *A blocks B*. Pass the **blocker first**. Getting this backwards silently builds the dependency graph in reverse.
- **`jira issue list` paginates at 100** (`--paginate <from>:<limit>`, default `0:100`, max 100 per call). A frontier query over a big epic truncates without saying so — page explicitly and say what you covered.
- **`jira issue assign` needs an exact email or display-name match.** `$(jira me)` for self, `default` for the project default, `x` to unassign. It won't fuzzy-match a username.

Status names in `jira issue move` are per-workflow — read them off `jira issue view` rather than assuming `Done`; real boards carry things like `In Develop` and `Ready For Production`. `jira epic add` takes at most 50 issues per call. Default list order is `created` DESC (`--order-by`, `--reverse`).

**Team-managed (next-gen) projects** have no separate *Epic Name* field, which is what `jira epic create -n` writes. If `-n` errors or is ignored, create the epic as a plain issue instead — `jira issue create -tEpic -s"<summary>" --no-input` — and parent children to it with `-P<EPIC-KEY>` as usual. Check with `jira project list` / the `project.type` in `~/.config/.jira/.config.yml` (`next-gen` = team-managed).

**Fallback: the connected Atlassian MCP tools.** Use these when `jira` is absent or unauthenticated:

- **Create an issue**: `createJiraIssue` with the project key, issue type, summary, and description.
- **Read an issue**: `getJiraIssue` by key (e.g. `ABC-123`). Comments come back with the issue.
- **List / query issues**: `searchJiraIssuesUsingJql` — e.g. `project = ABC AND labels = needs-triage AND statusCategory != Done ORDER BY created DESC`.
- **Comment**: `addCommentToJiraIssue`.
- **Apply / remove labels**: `editJiraIssue` on the `labels` field. Jira labels are free-form, so the five canonical triage roles work as literal label strings — no remapping needed.
- **Close**: `transitionJiraIssue` (check `getTransitionsForJiraIssue` first — transition names are per-workflow, not universal).

If neither a CLI nor an MCP server is available, use the Jira REST API via `curl` with a token, and tell the user that's what you're doing.

If this repo already has a house style for ticket titles and bodies, follow it — check for a ticket-writing skill or a convention documented in `AGENTS.md` / `CLAUDE.md` before inventing a format.

## Issue operations (legacy `bkt issue`, Cloud only, until 20 Aug 2026)

Only if **Issue home** above is set to `bitbucket-native`. `bkt` prints a sunset warning on every one of these calls.

- **Create**: `bkt issue create -t "..." -b "..." -k task` — `--kind` defaults to `bug`, so pass it (`task`, `enhancement`, `proposal`).
- **Read**: `bkt issue view <id> --comments`, or `--json`.
- **List**: `bkt issue list --state open --limit 100 --json`. Filters: `--kind`, `--priority`, `--assignee`, `--milestone`, `--state`.
- **Comment**: `bkt issue comment <id> -b "..."`; read with `--list`.
- **Edit**: `bkt issue edit <id> --state <s> --component <c> --kind <k> --priority <p>`.
- **Close / reopen**: `bkt issue close <id>` / `bkt issue reopen <id>`. No close-with-comment flag — comment first, then close.
- **Your queue**: `bkt issue status` — issues assigned to you, created by you, recently updated.

`bkt issue delete <id>` exists and is irreversible; it prompts unless `--confirm` is passed. Don't reach for it — close or mark `invalid` instead.

Assignees are **UUIDs in braces** (`-a "{abc-123}"`), not usernames. Resolve one; don't invent it.

Bitbucket Cloud issues have **no free-form labels**, so the triage roles ride on native fields:

| Canonical role    | Carrier                                   | Command                                           |
| ----------------- | ----------------------------------------- | ------------------------------------------------- |
| `needs-triage`    | state `new` (Bitbucket's own "untriaged")  | `bkt issue edit <id> --state new`                 |
| `needs-info`      | state `on hold`                            | `bkt issue edit <id> --state "on hold"`           |
| `ready-for-agent` | component `ready-for-agent`                | `bkt issue edit <id> --component ready-for-agent` |
| `ready-for-human` | component `ready-for-human`                | `bkt issue edit <id> --component ready-for-human` |
| `wontfix`         | state `wontfix`                            | `bkt issue edit <id> --state wontfix`             |

States are mutually exclusive, so the three state-carried roles can't collide — leaving triage means `--state open`. Components must **already exist** in repo settings (Bitbucket won't create them on demand the way GitHub auto-creates labels); if they don't and you can't add them, put a `Triage: ready-for-agent` marker as the first line of the issue body and read it back with `bkt issue view <id> --json --jq '.content.raw'`. Say which mechanism you used. `resolved` / `invalid` / `duplicate` are extra native states with no canonical role — use them on their own terms.

## Pull requests

`bkt pr` works on **both** Cloud and Data Center, and is unaffected by the Issues sunset.

- **Read**: `bkt pr view <id> --json`, `bkt pr comments <id>`, `bkt pr diff <id>`.
- **List**: `bkt pr list --state OPEN --limit 50 --json` (`--mine` to scope to yourself).
- **Create**: `bkt pr create --title "..." --body "..." --reviewer <user>`. Don't invent reviewer usernames.
- **Comment**: `bkt pr comment <id> --text "..." [--file path --to-line N]` for inline.
- **CI status**: `bkt pr checks <id>`, or `bkt status pr <id>` on Data Center.
- **Merge**: `bkt pr merge <id> --strategy squash`. **Confirm with the user first** — there's no dry-run gate.

### PRs as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

Two differences from GitHub if you turn this on:

- **No `authorAssociation`.** Bitbucket's PR payload doesn't say whether the author is a workspace member, so you can't cheaply filter external contributors the way `gh` allows. Judge by author account, or query workspace membership via `bkt api` and diff against it.
- **Separate number spaces.** Bitbucket PR ids are their own sequence, independent of Jira keys — no `#42` ambiguity, but always name the surface (`PR 42` vs `ABC-42`).

## When a skill says "publish to the issue tracker"

Create a Jira issue in `<PROJECT-KEY>` (or a Bitbucket issue if **Issue home** is `bitbucket-native`).

## When a skill says "fetch the relevant ticket"

`jira issue view <KEY> --comments 20` (or `bkt issue view <id> --comments` for the legacy path).

## Wayfinding operations

Used by `/wayfinder`. The **map** is one issue with **child** issues as tickets. On Jira this maps onto native structure — better than the body conventions GitHub needs:

- **Map**: an Epic holding the Notes / Decisions-so-far / Fog body — `jira epic create -n"<name>" -s"<summary>"`, then `jira epic list` to find it again.
- **Child ticket**: an issue parented to the map — `jira issue create -tTask -P<MAP-KEY> -l wayfinder:<type> --no-input`, where type is `research`/`prototype`/`grilling`/`task`. Claimed tickets are assigned to the driving dev.
- **Blocking**: a native issue link — `jira issue link <BLOCKER> <BLOCKED> Blocks` (**blocker first** — see the traps above). A ticket is unblocked when every blocker reaches a `Done` status category. (Via MCP: `createIssueLink`, and check `getIssueLinkTypes` — link-type names vary per instance.)
- **Frontier query**: `jira issue list -q 'parent = <MAP-KEY> AND statusCategory != Done AND assignee IS EMPTY ORDER BY rank' --raw`, then drop any with an open blocker link. Watch the 100-issue page limit on a large map.
- **Claim**: `jira issue assign <KEY> $(jira me)` — the session's first write.
- **Resolve**: `jira issue comment add <KEY> "<answer>"`, then `jira issue move <KEY> "<done status>"`, then append a context pointer to the map's Decisions-so-far.

On the legacy Bitbucket-native path none of this exists — no sub-issues, no dependencies. Use `Part of #<map>`, `Wayfinder: <type>`, and `Blocked by: #<n>` lines at the top of issue bodies, with a task list in the map body as the ordered index.
