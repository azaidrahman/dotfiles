---
name: worklog
description: Use when the user runs /worklog start or /worklog stop, or asks to sync their assigned Jira tickets into today's Obsidian daily journal or recap the work day. start pulls Jira issues assigned to the user into the Professional tasks of today's entry; stop refreshes that checklist and adds a narrative recap plus a next-day look-ahead.
---

# worklog

Bridges Jira and the Obsidian daily journal. Two modes, invoked manually.

## When to use

- `/worklog start` - beginning of the work day: pull the user's open Jira
  tickets, discuss with them what to focus on today, then write the agreed set
  into today's journal as a Professional task checklist.
- `/worklog stop` - end of the work day: refresh the checklist against Jira,
  then write a narrative recap of the day and a short look ahead at next day's
  likely tasks.

If the user invokes `/worklog` with no argument, ask whether they mean `start`
or `stop`.

## Fixed facts

- Vault root: `/Users/abdullahzaidas-sani/Documents/Zaid Personal`. The
  `Documents - GB07162's MacBook Pro/Zaid Personal` copy is an old backup and is
  never touched.
- Today's entry path: `<vault>/2-Journals/Entry/<ddd, DD-MM-YYYY>.md`. Build the
  filename with `date "+%a, %d-%m-%Y"`, e.g. `Wed, 03-06-2026`.
- Entry template: `<vault>/98-Templates/Journal Template.md`.
- Jira: use the connected Atlassian MCP. The cloud id comes from
  `getAccessibleAtlassianResources`; current user from `atlassianUserInfo`;
  issues from `searchJiraIssuesUsingJql`.

## Obsidian rules (from obsidian-note-template)

- Never write the em dash character U+2014 in any output. Use a plain hyphen with
  spaces ( - ) instead.
- Do not add a top-level `# Title` heading; do not touch existing tags.
- Only edit inside the worklog marker regions described below, plus creating a
  missing entry file from the template in `start`.
- Keep prose concise.

## Marker regions

All generated content lives under the `**Professional**` line inside `# Tasks`,
inside hidden HTML-comment markers (invisible in Obsidian reading view):

- Checklist region: between `<!-- worklog:start -->` and `<!-- worklog:end -->`.
- Recap region (stop only): between `<!-- worklog:recap-start -->` and
  `<!-- worklog:recap-end -->`, placed immediately after the checklist region.

Re-running a mode rewrites the content inside these markers in place. Never
duplicate the markers and never edit outside them.

## start procedure

This mode is a conversation, not a dump. Pull the user's open work, talk through
priorities with them, and only write the set they choose to focus on today.

1. Compute the entry path:
   `date "+%a, %d-%m-%Y"` gives the filename stem. The full path is
   `<vault>/2-Journals/Entry/<stem>.md`.
2. If the entry file does not exist, create it: copy
   `98-Templates/Journal Template.md`, replace the `{{time}}` placeholder with
   the current time from `date "+%H:%M"`. Do not add any other content.
3. Resolve Jira access:
   - Call `getAccessibleAtlassianResources` and take the first resource's `id`
     as the cloud id and its `url` as the site base.
4. Query open issues with `searchJiraIssuesUsingJql`:
   - cloudId: from step 3.
   - jql: `assignee = currentUser() AND statusCategory != Done ORDER BY status ASC, updated DESC`
     (Done/Closed are excluded on purpose - the morning list is about open work.)
   - fields: `["summary", "status"]`
   - maxResults: 50
   - The response can be large. If the tool reports the result was saved to a
     file because it exceeded the size limit, extract just key, status, and
     summary with `jq`, e.g.
     `jq -r '.issues.nodes[] | "\(.key)\t\(.fields.status.name)\t\(.fields.summary)"' <file>`.
5. Discuss with the user. Present the open tickets grouped by status (key,
   summary, status - concise), then ask which they want to focus on today. Let
   them pick a subset, reprioritise, or name extra tasks that are not in Jira.
   Wait for their decision before writing anything.
6. Build the checklist from what was agreed - the day's chosen tasks only:
   - Jira task: `- [ ] [KEY](<site>/browse/KEY) <summary> - <status name>`
   - Non-Jira task the user named: `- [ ] <task text>`
   - If the user chooses nothing, render a single line: `- no focus set today`.
7. Read the entry file. Build the checklist block:
   ```
   <!-- worklog:start -->
   <rendered lines>
   <!-- worklog:end -->
   ```
8. Insert or replace:
   - If `<!-- worklog:start -->` already exists, replace everything from that
     marker through `<!-- worklog:end -->` (inclusive) with the new block.
   - Otherwise, insert the block on the line immediately after the
     `**Professional**` line.
   Use the Edit tool with the exact existing text as `old_string`.
9. Before saving, confirm the new content contains no U+2014 character.
10. Report to the terminal: number of tasks written and the entry path.

## stop procedure

1. Compute the entry path (same as start, step 1).
2. If the entry file or the `<!-- worklog:start -->` marker does not exist, run
   the entire `start procedure` first so a checklist exists, then continue.
3. Read the checklist region and collect the Jira ticket keys already chosen for
   today. Re-query just those with
   `searchJiraIssuesUsingJql`, jql `key in (KEY1, KEY2, ...)`, fields
   `["summary", "status"]`. This catches tickets that moved to Done during the
   day. (Non-Jira checklist lines are left as the user left them.)
4. Rewrite the checklist region (between `<!-- worklog:start -->` and
   `<!-- worklog:end -->`) with refreshed lines: update each ticket's status
   text and flip any now-Done ticket to `- [x]`. Same rendering rules as start,
   step 6.
5. Build the recap region and place it immediately after `<!-- worklog:end -->`:
   ```
   <!-- worklog:recap-start -->
   <narrative paragraph>

   Next day: <look-ahead sentence or two>
   <!-- worklog:recap-end -->
   ```
   - Narrative paragraph: a few plain sentences recapping the day, grounded in
     what changed between the morning checklist (if visible) and now - tickets
     closed, moved, or newly assigned. No em dashes.
   - Next day: name the likely tasks to pick up - tickets still In Progress or
     newly To Do, and the natural next step on anything closed today.
   - If the recap region already exists, replace its contents in place.
6. Before saving, confirm no U+2014 character is present.
7. Report to the terminal: counts of done vs open tickets and the entry path.
