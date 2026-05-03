---
name: obsidian-note-template
description: Use when creating or editing Obsidian vault notes in this project. Enforces the user's note template, no title heading at the start, nested tags, no em dash characters, and light baseline notes that the user can expand.
---

# Obsidian Note Template

## When to use

Use this skill whenever the user asks you to create, draft, edit, organize, or connect Obsidian notes in the vault.

## Hard rules

- Never add the em dash character, U+2014, in generated note prose or metadata.
- Do not add a top title heading like `# <TITLE>` at the start of a note.
- Obsidian already shows the note title from the filename.
- Prefer nested vault tags, not flat tags.
- Do not create a new top-level tag unless the user explicitly approves it first.
- Keep generated notes concise unless the user asks for a fuller draft.
- Write a clear baseline so the user can add their own thoughts.

## New note template

Every new Obsidian note must follow this shape:

```md
---
tags:
  - nested/tag/example
created date: YYYY-MM-DD
created time: HH.MM AM
---
# Intro

Short baseline explanation.

# Reference

- [[Related note]]
```

## Workflow

1. Locate the vault path from `.env` or the user's request.
2. Read existing related notes before creating new notes.
3. Reuse existing notes when appropriate instead of creating duplicates.
4. If a note already exists, edit it instead of creating a competing note.
5. Add backlinks from relevant existing notes when helpful.
6. Verify generated or edited notes contain no em dash characters.

## Tag guidance

Use nested tags under existing top-level categories, for example:

- `tech/networking`
- `tech/networking/sockets`
- `tech/linux/file-descriptors`
- `tech/tools/socat`

If a new top-level category seems necessary, ask first.

## Style guidance

The user's preferred note style is:

- simple
- connected with wikilinks
- not over-written
- enough structure to start writing independently
- practical mental models and commands when useful
