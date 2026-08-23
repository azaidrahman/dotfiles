---
name: design-record
description: Use when writing a design document, a decision record, an architecture proposal, or a research synthesis as an Artifact. Triggers include "write this up as a design doc", "make a decision record", "turn the research into a document", "write the spec for this", "document the architecture". Gives every such page the same fixed shape, so the reader always finds the same thing in the same place.
---

# Design Record

## Overview

Build a design document as a published Artifact, in one fixed shape.

The value is repetition. The reader learns the shape one time, then finds
the problem, the mechanism, the plan, and the evidence in the same place
in every document. Do not invent a new structure for each subject.

**The deliverable is a published Artifact.** The link is the output.

## When not to use

| The user wants | Use instead |
|---|---|
| An explanation of a code change | `explain-diff` |
| Bugs and defects found | `/code-review` |
| A visual mockup or a screen design | `design` |
| A short answer | Answer in the chat |

## The reading contract

Every page keeps this order. The reader depends on it.

1. **Masthead.** The name, one sentence, and the status.
2. **Part one is always the problem.** What hurts, and what it costs.
3. **The middle parts are the mechanism.** How the thing works.
4. **The last part is always the plan.** What to build, in what order,
   and what is still open.
5. **The appendix is always evidence, limits, and sources.**

## Rules

**Use three to five parts. Never more than five.** One idea in each
part. If a part holds two ideas, split it or merge one away. Name each
part for its idea, not for its category. Write "Sprawl costs output",
not "Background".

**Put each decision in the part that it belongs to.** Do not collect
the decisions into one block at the end. A decision carries an id
(`D-01`), a one-line claim, and a **Why** line. If the reason stops
holding, the decision reopens.

**Mark every claim with its evidence strength.** Use exactly three
words, and no others:

| Chip | Meaning |
|---|---|
| `measured` | A controlled result exists. Build on it. |
| `narrative` | Described somewhere, never measured. Cheap to do, unproven. |
| `opinion` | Your judgement. No evidence either way. |

Never promote a claim to `measured` because it feels correct. If you
find that an earlier draft overstated a claim, lower the chip and say
so in the page. The chips decide the build order, so they must be
honest.

**Draw three to six small figures.** Use inline SVG. Never use an ASCII
diagram. One figure makes one claim. Give each figure a caption that
states the claim, and an `aria-label` that carries the same words. Show
the mechanism, not the name of the mechanism. Label every arrow.

**Show a user interface as HTML, not as text in a `pre` tag.** A
terminal view, a board, or a form is a picture. Build it from real
elements, with real colour.

**Keep the index sticky.** The reader must always know the position,
and must always be able to jump. Use the template, which supplies a
left rail with scroll tracking on a wide screen, and a top bar with a
jump menu on a narrow screen.

**Write in Simplified Technical English.** Short sentences. Active
voice. One idea in each sentence. The condition comes first.

## Steps

1. Read `template.html` beside this file. It holds the tokens, the
   component classes, and the index script. Copy it, then fill the
   slots. Do not rebuild the shell.
   **Delete the instruction comment at the top of the copy.** It must
   never reach the published page.
2. Load `artifact-design` for the design pass, and
   `artifact-diagramming` before you draw.
3. Choose the accent colour for the subject. **This is the only visual
   freedom.** Keep the type pairing, the layout, the spacing, and the
   component classes as they are. Consistency is the point.
4. Write the parts. Give each `<section>` an `id`, a `data-num`, and a
   `data-label`. The index builds itself from those attributes.
5. Write the appendix: an evidence table, a limits note, and sources.
6. Name the page. Use a short noun phrase, two to four words, specific
   to the subject. Add no explainer after a dash or a colon.
7. Save the file to `$CTX_DIR`. Get the date with `date +%F`. Name the
   file `YYYY-MM-DD-design-<slug>.html`.
8. **Check the page before you publish.** Run these three checks. Each
   one has failed in practice.

   ```bash
   f=YOUR_FILE.html
   grep -c REPLACE "$f"                       # must be 0
   grep -c 'DESIGN RECORD TEMPLATE' "$f"      # must be 0
   # every class used in the body must have a rule in the stylesheet:
   comm -23 \
     <(sed -n '/<\/style>/,$p' "$f" | grep -o 'class="[^"]*"' \
        | tr ' "' '\n\n' | sed 's/^class=//' | grep . | sort -u) \
     <(sed -n '1,/<\/style>/p' "$f" | grep -o '\.[a-zA-Z][-a-zA-Z0-9_]*' \
        | sed 's/^\.//' | sort -u)
   ```

   The third check must print nothing. If it prints a class, that
   element renders unstyled. This happens when you copy content from an
   older page whose stylesheet held a component that the template does
   not.

9. Publish with the `Artifact` tool. Hand the link to the user.

To update the page later, edit the file and publish it again with the
same `url`. If a later session does not hold the link, find it with
`action: "list"`.

## The limits note is not optional

Every page carries a limits section. State what the research could not
reach, which citations you did not verify, and which load-bearing
claims are unmeasured. A page that hides its weak points cannot be
trusted, and a reader who finds one unmarked weak point stops trusting
the strong parts too.

## Deliberate conflict with artifact-design

`artifact-design` asks for a distinctive visual identity for each
subject. This skill overrides that, because the user wants one
repeatable shape. Keep the fixed structure and the fixed components.
Spend the per-subject judgement on the words, the figures, and the
accent colour.

## Common mistakes

| Mistake | Fix |
|---|---|
| Six or more parts. | Merge until five remain. |
| A part named for a category, such as "Context". | Name it for its idea. |
| Decisions collected at the end. | Move each decision into its part. |
| A claim with no chip. | Add the chip, or delete the claim. |
| A claim marked `measured` with no number. | Give the number, or lower the chip. |
| An ASCII diagram. | Redraw it as inline SVG. |
| No limits section. | Add it. It is not optional. |
| A new colour system for each page. | Change the accent only. |
| The template instruction comment reached the page. | Delete it in step 1. Check it in step 8. |
| An element renders unstyled. | Run the class check in step 8. Add the missing component to the template. |
| A structure check counts the wrong thing. | Count `data-num`, never `data-apx`. The instruction comment also holds that word. |
