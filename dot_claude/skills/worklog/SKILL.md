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
- Only edit the owned region (defined below), plus creating a missing entry file
  from the template in `start`. Never touch other sections of the entry.
- Keep prose concise.

## Owned region

The skill manages exactly one region of the entry: the block of lines between
the `**Professional**` line and the next top-level heading (`# Meetings`). No
HTML comments or markers are ever written into the note. On every run this block
is rewritten in place, so re-running never duplicates content. Keep one blank
line before `# Meetings`. Nothing outside this region is touched.

## Length limit

Keep the entry tight - it must not grow over time.

- One line per task, about 100 characters maximum. Format
  `- [ ] [KEY](<site>/browse/KEY) <short label> - <status name>`.
- Use a short label of a few words, not the full Jira summary when it is long.
  Never append branch names, PR state, or multi-clause prose to a task line.
- Only the focus set chosen for the day goes in the checklist (usually a handful
  of lines), never the full open backlog.
- The stop recap is at most three short sentences plus one `Next day:` line.

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
6. Build the checklist from what was agreed - the day's chosen tasks only,
   obeying the length limit above:
   - Jira task: `- [ ] [KEY](<site>/browse/KEY) <short label> - <status name>`
   - Non-Jira task the user named: `- [ ] <short task text>`
   - If the user chooses nothing, render a single line: `- no focus set today`.
7. Determine the owned region: the lines from just after the `**Professional**`
   line up to the next top-level heading (`# Meetings`).
8. Replace that region with the rendered checklist followed by one blank line.
   Use the Edit tool, matching the existing region text as `old_string`. If the
   region is empty (fresh template), insert the checklist right after the
   `**Professional**` line.
9. Before saving, confirm the new content has no U+2014 character and that each
   task line stays within the length limit.
10. Report to the terminal: number of tasks written and the entry path.

## stop procedure

1. Compute the entry path (same as start, step 1).
2. If the entry file or a Professional checklist does not exist, run the
   `start procedure` first so a checklist exists, then continue.
3. Read the owned region and collect the Jira ticket keys in the checklist.
   Re-query just those with `searchJiraIssuesUsingJql`, jql
   `key in (KEY1, KEY2, ...)`, fields `["summary", "status"]`. This catches
   tickets that moved to Done during the day. Non-Jira lines are left as the
   user left them.
4. Rebuild the checklist: refresh each ticket's status text and flip any
   now-Done ticket to `- [x]`. Same rendering and length rules as start, step 6.
5. Append a recap below the checklist, inside the same owned region:
   ```
   <narrative recap>

   Next day: <look-ahead>
   ```
   - Narrative recap: at most three short sentences on what changed today
     (tickets closed, moved, or newly assigned). No em dashes.
   - Next day: the likely tasks to pick up - tickets still in progress and the
     natural next step on anything closed today. One line.
   - If a recap is already present, replace it in place (do not stack recaps).
6. Replace the owned region (checklist plus recap, then one blank line before
   `# Meetings`). Confirm no U+2014 character is present.
7. Report to the terminal: counts of done vs open tickets and the entry path.
