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
- Only state a specific fact, mechanism, command, flag, version, or external link if you can validate it against a real, current source this session. See `Writing your own input`.

## Note types

Decide which kind of note this is first, because the skeleton differs:

- **Concept note** explains an idea (theory, mental model, how something works). Gets the full skeleton.
- **Reference snippet** is a short command or fact lookup. Gets a trimmed skeleton.

## Section skeleton

This is a recommended skeleton, not a rigid form. Start from it and use the canonical headings below in this order. You may add one topic-specific heading when a concept genuinely needs it, but prefer reusing a canonical name over inventing a new one. Omit optional sections that have nothing to say rather than padding them.

Canonical headings, in order:

1. `# Intro` (always) short baseline explanation.
2. `# Mental model` (optional, concept notes) the intuition or analogy.
3. `# How it works` (optional) the mechanism, step by step.
4. `# Example` (optional) a concrete worked case.
5. `# Commands` (optional) runnable commands, in a fenced block.
6. `# Further reading` (recommended) links to external sources for extra reading: docs, articles, videos, specs. This is separate from `# Reference`, which is internal vault wikilinks. The user wants external sources captured, so include this whenever the note draws on or relates to anything external, with a one-line note on what each link covers.
7. `# Reference` (always) wikilinks to related notes.

Do not add a `# My own words` section, or any other empty placeholder section for the user to fill in. The user writes their own thoughts themselves; an empty heading is noise. Only write sections you are actually filling with content.

Frontmatter is fixed and always leads the file:

```md
---
tags:
  - nested/tag/example
created date: YYYY-MM-DD
created time: HH.MM AM
---
```

**Never guess `created date` or `created time`.** Run `date` in the shell and use its real output. A guessed timestamp is a fabricated fact like any other, and the system date in context may only give the day, not the time.

Concept note shape:

```md
# Intro

Short baseline explanation.

# Further reading

- [Source title](https://example.com) what it covers.

# Reference

- [[Related note]]
```

Reference snippet shape:

```md
# Intro

Short baseline explanation.

# Further reading

- [Source title](https://example.com) what it covers.

# Reference

- [[Related note]]
```

## Workflow

1. Resolve the vault root from `$OBSIDIAN_VAULT` (the Polaris vault). Fall back to the path in the user's request only if that variable is unset.
2. **Search the vault for the concept first.** Read any related notes before writing anything.
3. Before writing frontmatter on a new note, run `date` in the shell and format its output as `YYYY-MM-DD` and `HH.MM AM/PM`. Do not write a timestamp from memory or context.
4. **Creation gate, edit by default.** Default to editing or extending an existing note. Only create a brand-new file when the concept has no home AND would not fit as a section under an existing note. State which you chose and why before acting.
5. **When creating a brand-new file, start from the vault's base template at `98-Templates/Note Template.md`.** Read it first, then build the note on top of its exact frontmatter field order and shape, replacing `{{date}}`/`{{time}}` with the real values from step 3. Do not hand-write frontmatter from the skeleton below without reading the template first; the template file is the source of truth and this skeleton must stay consistent with it.
6. If the concept fits inside an existing note, add it there as a section rather than as a competing file.
7. After creating or editing a note, always add backlinks to it from the related existing notes you found in step 2. This is a default step, not optional. Place each backlink contextually where it is relevant in the neighbor note, and also add it to that note's References section. Keep each backlink to a short, natural sentence so neighbor notes are not over-written.
8. When two related notes exist, give each a one-line pointer near the top naming the sibling and what it is for (for example, a theory note points to its worked example and back). This keeps their relationship self-documenting.
9. Verify generated or edited notes contain no em dash characters.

## Writing your own input

When you write the substance of a note yourself, keep the lightweight style above. But lightweight is not a license to fill the baseline with plausible-sounding facts from memory. The user keeps these notes long-term and trusts them, so an unverified specific is worse than a thinner note.

Rule: only assert a specific claim as fact if you validated it against a real, up-to-date source this session. Specifics that need validation include mechanisms and behaviors, command syntax and flags, version numbers, API or config field names, RFC/section numbers, and every external link.

How to validate:

- Commands, flags, and tool behavior: run the tool (`--help`, a real invocation) and write what it actually output, not what you expect.
- Library, framework, or API facts: fetch current docs (use context7 or the official docs) and write from what you read.
- General technical facts you cannot check live: search the web to confirm before stating them.
- External links under `# Further reading`: fetch the URL and confirm it exists and covers what you say it covers. Never write a link or a section anchor from memory.
- Vault facts (which notes exist, what a neighbor says, whether a backlink target is real): search and read the vault first, as the workflow already requires.

If you cannot validate something, do one of these instead of asserting it:

- Leave that part out and keep the note thinner, so the user can fill it in themselves.
- Mark it explicitly as unverified, for example a short `[!NOTE]` callout saying "unverified, confirm before relying on this".
- Ask the user, or say plainly in your reply that you left it out because you could not confirm it.

Do not paper over a guess with hedging prose ("typically", "generally", "I believe") and present it as a baseline fact. Either validate it, mark it unverified, or leave it out.

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

## Emphasis: bold and italics

Keep emphasis minimal and sparse. The goal is readability, so most prose should carry no styling at all. Unstyled is the correct default, not a gap to fill. If a paragraph has more than one or two styled spans, you are over-using it; rewrite the sentence instead of reaching for emphasis.

- **Bold** marks a key term the first time it is introduced and being defined, for example **a router** in the sentence that explains what a router is. Use it once per term, not on every later mention.
- *Italics* mark an inline literal: a config field name, a file value, a flag, or a proper-name expansion of an acronym. For example *nameserver*, *net.ipv4.ip_forward*, or *Dynamic Host Configuration Protocol*.
- Do not bold or italicise words purely for emphasis ("this works *only* locally", "you must **not**"). If a point needs that much weight, the sentence structure should carry it, or it belongs in its own line or list item.
- Never style whole sentences or headings. Code, commands, and identifiers that are runnable or exact go in backticks, not italics.

## Defining terms and marking external info

Use a blockquote led by an italic question to define a key term, especially when the explanation comes from an external source (a video, article, docs, a person) rather than your own synthesis. The question frames what is being defined; the lines under it answer it in plain words. This keeps externally-sourced facts visually distinct as quoted material rather than the user's own synthesis.

```md
> *What is a bridge?*
> Acts as a switch between containers. It is a routing table between MAC addresses and their veth. It self-learns from traffic: it checks where a MAC address came from and on which veth.
```

- Use it for a definition or a quoted/paraphrased fact that originated outside the note, not for every sentence.
- Keep the answer short and in plain language; it is a baseline, not an essay.
- Reserve the italic-question line for one term per blockquote.
- When the fact comes from a specific source worth revisiting, also add that source under `# Further reading`.

## Callouts for warnings, notes, and reminders

Use an Obsidian callout for content that should visually break out of the flow: a gotcha, a warning, a reminder, a tip, or a side note the reader must not miss. A callout is a blockquote whose first line is `> [!TYPE] Optional title`, with the body on following `>` lines.

```md
> [!WARNING] If a ping between namespaces fails
> Set the netmask when assigning the IP, otherwise the kernel assumes a /32 and the peer looks unreachable.
> Also check that firewall rules are not dropping the traffic.
```

- Pick the type by intent: `[!WARNING]` or `[!CAUTION]` for things that bite you, `[!TIP]` for a shortcut or best practice, `[!NOTE]` or `[!INFO]` for a neutral aside, `[!IMPORTANT]` for something that must not be skipped.
- Give the callout a short title that states the takeaway, not a generic label. "If a ping between namespaces fails" beats "Warning".
- Keep the body tight; a callout is a flag, not a section. Use a short list inside it when there are two or three checks.
- Reserve callouts for genuine breakouts. Do not wrap ordinary prose in one, and do not use a callout where the italic-question blockquote above is the right tool (defining an externally-sourced term).
- This is distinct from the definition blockquote: that one defines a term, a callout flags a warning, reminder, or tip.

## Diagram guidance

Favor diagrams when they make a concept click faster than prose, for example flows, decision trees, hops, layered systems, or relationships between parts. Do not add them for their own sake; skip them when a sentence or short list is already clear.

- **Default to D2** fenced code blocks (` ```d2 `). The vault has the `d2-obsidian` plugin and the `d2` CLI installed, so D2 renders inline. D2 gives cleaner containers, styling, and color, and matches the look the user prefers.
- **Always compile-check D2 before writing it into a note.** Write the source to a temp file and run `d2 <file>.d2 /tmp/out.svg`. Only paste blocks that compile cleanly.
- Orient diagrams top-down (`direction: down`) rather than left-right so they fit the note column and do not force horizontal scrolling. Split long chains onto separate lines for the same reason.
- **Color must carry meaning, or the node stays neutral.** Every color encodes one fixed role. A node that does not play one of those roles gets no `style.fill` at all (default/neutral). Never pick a color to decorate or to make a diagram "look nicer" — uncolored is the correct default, not a gap to fill.
- **Use this exact palette, the same hex in every diagram in the vault** (apply with `style.fill` / `style.stroke`). Do not invent new shades per note; reuse these so colors mean the same thing across notes:
  | Role | Meaning | fill | stroke |
  |------|---------|------|--------|
  | Blue | local / source / origin side ("you are here") | `#dbeafe` | `#2563eb` |
  | Red | remote / destination / the far end | `#fee2e2` | `#dc2626` |
  | Grey | infrastructure passed through, not the focus (routers, bridges, intermediate steps) | `#e5e7eb` | `#6b7280` |
  | Yellow (diamond) | a decision / branch point | `#fef9c3` | `#ca8a04` |
  | Green | success / resolved terminal outcome | `#dcfce7` | `#16a34a` |
- One role = one color. Do not reuse blue for both "source" and "default-route outcome" in the same note, and do not give one role two different hues across notes.
- No decorative styling: skip `font-color`, `stroke-dash`, `border-radius`, gradients, and shadows unless they themselves encode meaning the reader needs. If nothing on the list fits the concept, leave the whole diagram uncolored rather than reaching for a color outside the palette.
- Keep node labels short. Use `\n` for line breaks and avoid parentheses inside labels.
- Mermaid (` ```mermaid `) is the fallback only if D2 cannot render in the target environment.
- Use ASCII diagrams only when the shape is trivial or neither tool can express it.
- For freeform, hand-drawn sketches, note that Excalidraw is the better tool, but do not create those automatically.
