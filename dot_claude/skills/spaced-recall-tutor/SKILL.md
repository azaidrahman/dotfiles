---
name: spaced-recall-tutor
description: Use when you want to test your understanding of an Obsidian vault note right after learning it, quiz a broader concept that spans several notes, or run a spaced-repetition review of items that are due. Runs a Socratic free-recall quiz and tracks scores and next-due dates as stub notes under 99-Review/srs/ (viewable via the Spaced Recall.base file).
---

# Spaced Recall Tutor

## Overview

Test understanding through Socratic free-recall, then schedule for spaced review so
it sticks. Three modes: **Assess** a single note, **Concept** quiz across a hub note
and its linked notes, and **Review** what's due.

All state lives in **stub notes** under `99-Review/srs/` (one stub per tracked item),
viewable as a spreadsheet through `99-Review/Spaced Recall.base`. The SM-2-lite math
is computed by you.

**Never modify the original vault notes.** Do not append flashcards or review
sections to them. Do not delegate scheduling to an Obsidian SR plugin or cron. All
state goes in the stub notes; real notes are read-only sources.

Always read `quiz-rules.md` (in this skill's directory) at the start of a session.

## Mode selection

- "quiz me on [[note]]", "test me on X", "I just learned Y" -> **Assess** (one note).
- "quiz me on [[hub]] as a concept", "concept quiz on X" -> **Concept**.
- "what's due?", "run my review", "spaced repetition session" -> **Review**.

## Getting today's date

Run `date +%F` to get today as `YYYY-MM-DD`. Use it for all date math. Never guess.

## Stub notes: `99-Review/srs/<Topic> (review|concept).md`

One stub per tracked item. Single notes use `(review)`, concepts use `(concept)`.
Filenames are intentionally distinct from real note titles so they never collide in
link autocomplete. Frontmatter schema:

```yaml
---
tags:
  - review/srs
type: note            # "note" for a single note, "concept" for a hub-spanning concept
target: "[[Flannel]]" # the source note (Assess) or the hub note (Concept)
members:              # ONLY for type: concept — the constituent notes covered
  - "[[CNI]]"
  - "[[kube-proxy]]"
last_reviewed: 2026-06-14
next_due: 2026-06-17
interval: 3
ease: 2.6
last_score: 4
weak_spots:           # last 3 dated entries, newest last
  - "2026-06-14: same-node bridge vs vxlan backend"
---
```

- Dates are ISO `YYYY-MM-DD`. Ease is a float (floor 1.3). `weak_spots` keeps the
  last 3 entries only. Omit `members` for single-note stubs.
- To find an existing stub for a target, glob `99-Review/srs/*.md` and match the
  `target` property (do not rely on filename alone).

## Mode A: Assess (single note)

1. Read `quiz-rules.md`, then read the target note.
2. Run a 4-5 question Socratic session per the rules: one question at a time, wait
   for each answer, probe weak spots before moving on.
3. Assign a 0-5 score and a one-line dated weak-spots entry.
4. Find the stub whose `target` matches this note. If none, create one
   (`type: note`, new item: interval 1, ease 2.5). Reschedule (see Scheduling),
   update `last_score`, append the weak-spots entry (keep last 3).

## Mode C: Concept (hub spanning several notes)

1. Read `quiz-rules.md`, then read the hub note named in `[[...]]`. Collect its
   outgoing wikilinks as the candidate member set. Read the members you will use.
2. Bounded sampling: still ~4-5 questions. If the hub has many links, pick 2-4
   members for this session (favor ones flagged in past `weak_spots`; rotate so
   different members come up over time). Weight questions toward **synthesis** —
   how the members fit together (e.g. "how do kube-proxy and CNI interact?") — not
   just isolated recall.
3. Assign one 0-5 score for the concept and a dated weak-spots entry.
4. Find the stub whose `target` matches the hub. If none, create one
   (`type: concept`, `members:` = the links you used, new item: interval 1,
   ease 2.5). Reschedule, update `last_score`, append weak-spots (keep last 3).
   Concept stubs are scheduled independently of the members' own `(review)` stubs.

## Mode B: Review

1. Run `date +%F`. Glob `99-Review/srs/*.md` and read each stub's frontmatter.
2. Select stubs where `next_due <= today`. If none are due, say so and stop.
3. For each due stub: read `quiz-rules.md` and re-read the source.
   - `type: note` -> re-read `target`, run a single-note session.
   - `type: concept` -> re-read the hub `target`, re-expand its current links
     (so newly added notes get picked up), run a concept session.
   Generate fresh questions; do not reuse last session's.
4. Update `last_score`, append to `weak_spots`, reschedule. Leave not-due stubs
   untouched.

## Scheduling: SM-2-lite

Given the stub's current `interval` and `ease` and this session's `score`:

- New item (no stub yet): start from `interval = 1`, `ease = 2.5`, then apply the
  rule below using this session's score.
- Pass (`score >= 3`): `interval = round(interval * ease)`;
  `ease = ease + 0.1 * (score - 3)`.
- Fail (`score < 3`): `interval = 1`; `ease = max(1.3, ease - 0.2)`.
- `next_due = today + interval days`. `last_reviewed = today`.

## Common mistakes

- Editing the original note. Never. All state goes in `99-Review/srs/` stubs.
- Naming a stub identically to a real note (breaks link autocomplete). Use the
  `(review)`/`(concept)` suffix.
- Matching stubs by filename instead of the `target` property.
- Delegating scheduling to an Obsidian SR plugin or cron. You compute SM-2-lite.
- Asking all questions at once, or using multiple-choice. One at a time, free-recall.
- Concept mode quizzing all members every time. Sample 2-4, weight synthesis.
- Inventing the date. Always run `date +%F`.
- In Review mode, quizzing or rewriting stubs that are not yet due.
- Forgetting to floor ease at 1.3.
