# Issue tracker: Bitbucket

This repo lives on Bitbucket. Both surfaces go through one tool, `twg`:

- **Issues / PRDs → Jira**, via `twg jira workitem`. Bitbucket's own issue tracker is gone (see below).
- **Pull requests, code, pipelines → `twg bitbucket`.** `gh` does not work against Bitbucket.

```bash
twg whoami
```

If `twg` is not authenticated, run `twg login`. Do not run any setup, login, or
credential command unless the user asks for it. Report the problem and wait.

`twg bitbucket` accepts `bb` as a short alias. Both spellings appear below.

## Reading twg output in a script

`twg -o json` writes bare JSON to stdout only when stdout is a terminal. If
stdout is a pipe, twg writes a YAML envelope instead and puts the payload in a
temp file that `output_files.stdout` names. Read the envelope first, then read
the file it names.

Two shapes come back, and they differ by product:

- **Bitbucket** commands return the raw Bitbucket object or a **bare array**.
  A type guard is required: `.pull_requests` applied to an array is a hard jq
  error, not a null that `//` absorbs.
- **Jira** commands return a wrapper. `workitem query` puts rows in
  `.data.issues[]`; `workitem get` puts them in `.data`, which is an **array**
  even for one key.

```bash
# Unwrap a Jira workitem get. Test the array case FIRST - `.data.items` on an
# array throws before the later branches are reached.
jq 'if (.data|type) == "array" then .data[] elif .data.items then (.data.items[] | .data) else .data end'
```

## Why Jira and not Bitbucket Issues

**Bitbucket Cloud removed native Issues on 20 August 2026.** Bitbucket
**Data Center / Server never had an issue tracker** at all. There is no
remaining Bitbucket-native issue path, and `twg` has no
`bitbucket issue` command because there is nothing left to call.

**Issue home: `jira`.** There is no other option.

## Issue operations (Jira)

**Jira project key for this repo: `<PROJECT-KEY>`.**

| Operation | Command |
| --- | --- |
| Create an issue | `twg jira workitem create --space <PROJECT-KEY> --type Task --summary "<summary>" --description "<body>" --labels <a,b> --priority High` |
| Create under a parent | `twg jira workitem create --space <PROJECT-KEY> --type Story --parent <EPIC-KEY> --summary "..."` |
| Read an issue | `twg jira workitem get <KEY> --comments` |
| Read several issues | `twg jira workitem get <KEY-1> <KEY-2> <KEY-3>` |
| Fuzzy text search | `twg jira workitem search "<text>" --limit 20` |
| Query by JQL | `twg jira workitem query --jql '<JQL>' --limit 100` |
| Comment | `twg jira workitem comment create --issue-id <KEY> --body "<text>"` |
| Read comments | `twg jira workitem comment query --issue-id <KEY>` |
| Add labels | `twg jira workitem update --id <KEY> --add-labels <name>` |
| Remove labels | `twg jira workitem update --id <KEY> --remove-labels <name>` |
| List valid transitions | `twg jira workitem transitions query --id <KEY>` |
| Transition | `twg jira workitem update --id <KEY> --status "<Status Name>" --transition-comment "..."` |
| Transition many | `twg jira workitem bulk-transition --ids <KEY-1>,<KEY-2> --transition-id <id> --dry-run` |
| List issue types | `twg jira workitem types query --project-key <PROJECT-KEY>` |
| Assign / unassign | `twg jira workitem update --id <KEY> --assignee me` |
| Link a blocker | `twg jira workitem link workitem --id <BLOCKER> --target-id <BLOCKED> --link-type-id <id>` |
| List link types | `twg jira workitem link-types query` |
| List projects | `twg jira space query` |

Traps, all of them things that fail quietly:

- **`--add-labels` and `--remove-labels` are separate flags.** Plain `--labels`
  **replaces** the whole label set. Reach for `--labels` only when you intend
  to overwrite every existing label.
- **Link types are IDs, not names.** `link workitem` wants `--link-type-id`.
  Read the id off `twg jira workitem link-types query` first — `Blocks` is
  `10000` on some instances but you must not assume it. The link runs
  `--id` **blocks** `--target-id`, so pass the **blocker** as `--id`.
- **Status names are per-workflow.** Read them off
  `twg jira workitem transitions query --id <KEY>` rather than assuming `Done`.
  Real boards carry things like `Scheduled Tasks` and `Review`.
- **`--assignee` takes an account ID or the literal `me`.** It does not
  fuzzy-match a display name. Get an account ID from `twg whoami` or
  `twg user-search`.
- **Epics are a type, not a namespace.** There is no `epic` command. Create one
  with `--type Epic`, then parent children with `--parent <EPIC-KEY>`. Read the
  type names off `twg jira workitem types query --project-key <PROJECT-KEY>`
  rather than assuming them; that also shows each type's hierarchy level.
- **There is no bulk parent operation.** `update --id` takes exactly one key, so
  re-parenting a set means one call per issue. Say how many you changed.
- **`create-bulk` is not the friendly bulk creator it sounds like.** It is a raw
  GraphQL passthrough: `--issue-type-id` must be an **ARI**, not a name, and the
  issue data goes in a `--fields` JSON blob. It is board-oriented (`--board-id`,
  `--rank`, `--kanban-destination`). For a handful of tickets, loop plain
  `create` instead — it takes readable flags and a type name.
- **`bulk-transition` is the one real bulk command.** It takes `--ids` as a
  comma-separated list (or a repeated `--id`), wants a `--transition-id` rather
  than a status name, and is alone among the write commands in having
  `--dry-run`. Run the dry run first, then submit with `--yes`.
- **`query` needs real JQL; `search` takes plain text.** Passing text to
  `--jql` fails. Passing JQL to `search` searches for the literal string.
- **`--space` is documented as a project ID or ARI.** A project key resolves in
  practice. If `create` rejects the key, read the numeric id off
  `twg jira space get <PROJECT-KEY>` and pass that instead.
- **Paginate explicitly.** `--limit` caps the page. A frontier query over a big
  epic truncates silently, so page and say what you covered.

**Fallback: the connected Atlassian MCP tools.** Use these when `twg` is absent
or unauthenticated:

- **Create an issue**: `createJiraIssue` with the project key, issue type, summary, and description.
- **Read an issue**: `getJiraIssue` by key (e.g. `ABC-123`). Comments come back with the issue.
- **List / query issues**: `searchJiraIssuesUsingJql` — e.g. `project = ABC AND labels = needs-triage AND statusCategory != Done ORDER BY created DESC`.
- **Comment**: `addCommentToJiraIssue`.
- **Apply / remove labels**: `editJiraIssue` on the `labels` field. Jira labels are free-form, so the five canonical triage roles work as literal label strings — no remapping needed.
- **Close**: `transitionJiraIssue` (check `getTransitionsForJiraIssue` first — transition names are per-workflow, not universal).

`twg api <endpoint>` reaches the raw **Atlassian** REST API, so it is a last
resort for Jira only. It does **not** reach the Bitbucket API.

If this repo already has a house style for ticket titles and bodies, follow it — check for a ticket-writing skill or a convention documented in `AGENTS.md` / `CLAUDE.md` before inventing a format.

## Pull requests

`twg bb pull-requests` works on Cloud, and auto-detects the workspace and repo
from the git remote. Pass `-w <slug>` / `-r <slug>` only to override it.

- **Read**: `twg bb pull-requests get <id>` (add `--comments`, `--statuses`, `--diff`, or `--full`).
- **Diff**: `twg bb pull-requests diff <id>` for the raw unified diff.
- **List**: `twg bb pull-requests query --state OPEN --limit 50` (`--scope me` to scope to yourself, across every accessible repo).
- **Create**: `twg bb pull-requests create --title "..." --source <branch> --dest <branch> --description "..." --reviewer <account-id>`. Don't invent reviewer accounts.
- **Comment**: `twg bb pull-requests comment create --pull-request <id> --text "..."`. For inline, add `--path <file>` plus `--line N` (post-change side) or `--from-line N` (pre-change side).
- **CI status**: `twg bb pull-requests get <id> --statuses`.
- **Approve**: `twg bb pull-requests approve <id>`.
- **Merge**: `twg bb pull-requests merge --pull-request <id> --merge-strategy squash`. **Confirm with the user first** — there's no dry-run gate.

There is no `pull-requests checkout`. To review a PR locally, read
`source.branch.name` off `pull-requests get`, then fetch and check that branch
out yourself.

There is no draft or pending comment mode. Every comment is public the moment
it posts.

### PRs as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

Two differences from GitHub if you turn this on:

- **No `authorAssociation`.** Bitbucket's PR payload doesn't say whether the author is a workspace member, so you can't cheaply filter external contributors the way `gh` allows. Judge by author account, or list the workspace members with `twg bb workspace member query` and diff against that.
- **Separate number spaces.** Bitbucket PR ids are their own sequence, independent of Jira keys — no `#42` ambiguity, but always name the surface (`PR 42` vs `ABC-42`).

## When a skill says "publish to the issue tracker"

Create a Jira issue in `<PROJECT-KEY>`.

## When a skill says "fetch the relevant ticket"

`twg jira workitem get <KEY> --comments`

## Wayfinding operations

Used by `/wayfinder`. The **map** is one issue with **child** issues as tickets. On Jira this maps onto native structure — better than the body conventions GitHub needs:

- **Map**: an Epic holding the Notes / Decisions-so-far / Fog body — `twg jira workitem create --space <PROJECT-KEY> --type Epic --summary "<summary>"`. Find it again with `twg jira workitem query --jql 'project = <PROJECT-KEY> AND type = Epic ORDER BY updated DESC'`.
- **Child ticket**: an issue parented to the map — `twg jira workitem create --space <PROJECT-KEY> --type Task --parent <MAP-KEY> --labels wayfinder:<type>`, where type is `research`/`prototype`/`grilling`/`task`. Claimed tickets are assigned to the driving dev.
- **Blocking**: a native issue link — `twg jira workitem link workitem --id <BLOCKER> --target-id <BLOCKED> --link-type-id <id>`, with the id read off `link-types query` (**blocker first** — see the traps above). A ticket is unblocked when every blocker reaches a `Done` status category. (Via MCP: `createIssueLink`, and check `getIssueLinkTypes` — link-type names vary per instance.)
- **Frontier query**: `twg jira workitem query --jql 'parent = <MAP-KEY> AND statusCategory != Done AND assignee IS EMPTY ORDER BY rank' --limit 100`, then drop any with an open blocker link. Page explicitly on a large map.
- **Claim**: `twg jira workitem update --id <KEY> --assignee me` — the session's first write.
- **Resolve**: `twg jira workitem comment create --issue-id <KEY> --body "<answer>"`, then `twg jira workitem update --id <KEY> --status "<done status>"`, then append a context pointer to the map's Decisions-so-far.
