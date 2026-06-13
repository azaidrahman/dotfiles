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

## Note types

Decide which kind of note this is first, because the skeleton differs:

- **Concept note** explains an idea (theory, mental model, how something works). Gets the full skeleton including `My own words`.
- **Reference snippet** is a short command or fact lookup. Gets a trimmed skeleton, no `My own words`.

## Section skeleton

This is a recommended skeleton, not a rigid form. Start from it and use the canonical headings below in this order. You may add one topic-specific heading when a concept genuinely needs it, but prefer reusing a canonical name over inventing a new one. Omit optional sections that have nothing to say rather than padding them.

Canonical headings, in order:

1. `# Intro` (always) short baseline explanation.
2. `# Mental model` (optional, concept notes) the intuition or analogy.
3. `# How it works` (optional) the mechanism, step by step.
4. `# Example` (optional) a concrete worked case.
5. `# Commands` (optional) runnable commands, in a fenced block.
6. `# My own words` (concept notes only) left thin and mostly empty for the user to fill in. Never write this section densely.
7. `# Reference` (always) wikilinks to related notes.

Frontmatter is fixed and always leads the file:

```md
---
tags:
  - nested/tag/example
created date: YYYY-MM-DD
created time: HH.MM AM
---
```

Concept note shape:

```md
# Intro

Short baseline explanation.

# My own words

# Reference

- [[Related note]]
```

Reference snippet shape:

```md
# Intro

Short baseline explanation.

# Reference

- [[Related note]]
```

## Workflow

1. Locate the vault path from `.env` or the user's request.
2. **Search the vault for the concept first.** Read any related notes before writing anything.
3. **Creation gate, edit by default.** Default to editing or extending an existing note. Only create a brand-new file when the concept has no home AND would not fit as a section under an existing note. State which you chose and why before acting.
4. If the concept fits inside an existing note, add it there as a section rather than as a competing file.
5. After creating or editing a note, always add backlinks to it from the related existing notes you found in step 2. This is a default step, not optional. Place each backlink contextually where it is relevant in the neighbor note, and also add it to that note's References section. Keep each backlink to a short, natural sentence so neighbor notes are not over-written.
6. When two related notes exist, give each a one-line pointer near the top naming the sibling and what it is for (for example, a theory note points to its worked example and back). This keeps their relationship self-documenting.
7. Verify generated or edited notes contain no em dash characters.

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

## Diagram guidance

Favor diagrams when they make a concept click faster than prose, for example flows, decision trees, hops, layered systems, or relationships between parts. Do not add them for their own sake; skip them when a sentence or short list is already clear.

- Default to Mermaid fenced code blocks (` ```mermaid `), which Obsidian renders natively with no plugin.
- Orient diagrams top-down (`flowchart TD`) rather than left-right so they fit the note column and do not force horizontal scrolling. Split long chains onto separate lines for the same reason.
- Keep node labels short and avoid parentheses or special characters inside them, since Mermaid can fail to parse them.
- Use ASCII diagrams only when the shape is trivial or Mermaid cannot express it.
- For freeform, hand-drawn sketches, note that Excalidraw is the better tool, but do not create those automatically.
