---
name: teach
description: Use when the user wants to learn or understand a topic, asks "teach me X", "walk me through X", "I want to understand X", or asks for an explanation of a concept that is new to them. Runs a probe, plan, teach loop that builds understanding from unconditional truths, mirrors the lesson live to an Obsidian note, and ends with a spaced-repetition stub for spaced-recall-tutor. Not for quizzing a note the user already learned (use spaced-recall-tutor).
---

# Teach

Teach so that the topic is understood, not remembered. A fact that the learner can derive from foundations that they already accept stays. A fact that stands alone rots.

Read these two files at the start of every lesson:
- `quiz-construction.md` in this skill's directory
- `~/.claude/skills/spaced-recall-tutor/quiz-rules.md`

## Tunables

Edit these values to change the loop. Nothing else needs to change.

| Tunable | Value |
|---|---|
| Max bites per strand | 6 |
| Skip-ahead rule | 2 clean bites in a row: jump 2 bites |
| Probe depth on a miss | 1 follow-up question |
| SRS first interval | 2 days |
| SRS first ease | 2.5 |
| Lessons folder | `~/vaults/Polaris/5-Workbook/Lessons` |
| SRS folder | `~/vaults/Polaris/99-Review/srs` |

## The philosophy

Two brains can hold the same facts and answer the same questions. One holds a pile of lone facts. The other holds a few core truths from which the facts follow. The second brain understands. Connection is understanding.

The brain does not commit to a fact that is not safe. If something more basic might later contradict the fact, the brain hedges and the fact never lands. Both principles below remove that risk.

**Principle 1: Unconditional truths first.** Find the few facts that the learner can accept as they are, with no caveat. They lock in at once, because nothing deeper will contradict them. The strongest forms are universal statements ("ALL communication between computers is done through sending packets") and real definitions. Do not force one where there is none. Say "unconditional truth". Say "axiom" only for a fact that follows from nothing else.

**Principle 2: How could I have discovered this?** A fact feels arbitrary when there is no visible reason it had to be this way. Make it feel discovered, not decreed. Start from the problem. Motivate every step: why this formula, why this move. The reference is 3Blue1Brown. Nothing appears from nowhere.

Socratic or expository: pose the problem and let the learner attempt the discovery when they can plausibly reason there. Narrate the path yourself when the step is out of reach or the learner is tired.

## Accuracy

The learner must be able to trust the tutor. The moment you are not sure of a fact, a name, a date, a formula, or a definition, stop and dispatch `researcher` before you say it. If a check changes what you were about to teach, say so. A wrong root corrupts every node above it.

## Phase 0: Start

1. Run `date +%F`. Use this date everywhere. Never guess a date.
2. Find what the learner already has. Run `rg -il '<topic>' ~/vaults/Polaris/1-Notes/`. Read the notes found. Follow their wikilinks one level.
3. Read the SRS stubs for those notes in the SRS folder. Collect `last_score`, `weak_spots`, and `next_due`.
4. Create the lessons folder if it does not exist. Create the lesson note `<Lessons folder>/<Topic>.md` with this frontmatter and nothing else:

   ```yaml
   ---
   tags:
     - tech/learning/lesson
   topic: <Topic>
   started: <today>
   status: probing
   ---
   ```

   Use the tag root `tech/` for a technical topic, `life/` or `work/` otherwise. Never make a new top-level tag. Never write an em dash in the note. Never write a title heading at the top of the note.
5. Write the absolute path of the note to `~/.config/lesson-log`. Delete `~/.config/lesson-log.cursor` and `~/.config/lesson-log.session` if they exist. From now on the hook mirrors the session to the note.
6. Append `## Prior knowledge` to the note: the notes found, their scores, and their recorded weak spots. If nothing was found, write that the topic is new.

## Phase 1: Probe

Never skip this phase. Two unknowns, two tools.

### 1a. Verify the notes

Dispatch `researcher` with the topic and the specific claims from the learner's notes. Ask it to mark each claim confirmed, stale, or wrong, and to give the current first principles of the field. Append `## What changed` to the note with the stale and wrong claims. A stale claim is not a floor.

### 1b. The goal

Use `AskUserQuestion` to make the goal concrete. "Understand Flannel" can mean ten things. Ask until you can state the goal in one sentence. This question has no right answer, so it is never graded.

### 1c. Bite-sized walk and poke

For each strand that the goal depends on:

1. Split the strand into bites. Use the structure of the learner's note and the researcher's map. Respect the max bites per strand.
2. Set the scene in one or two sentences.
3. Ask one pointed question about the next bite, in free text. Rotate the question types from `quiz-rules.md`: predict the next step, what breaks if, trace this, why does this work. Never ask "explain X".
4. Grade the bite. Right: move on, and apply the skip-ahead rule. Wrong or vague: ask one follow-up on the exact gap, record the gap, move on. Do not teach yet.
5. Stop the strand when the edge is bracketed: one bite right and one bite wrong. All right means the bites were too easy. Go harder. One miss is not enough either. Probe around it.
6. Classify each miss with one or two `AskUserQuestion` multiple-choice questions built with `quiz-construction.md`: slip, isolated gap, or misconception. Always add a literal `I don't know` option. A misconception must be dislodged, not topped up.

Append `## Probe map` to the note. Per strand: the last solid bite, the first missed bite, and the type of each miss.

## Phase 2: Plan

Think hard here. This is the highest-leverage step.

1. List the unconditional truths that the goal rests on.
2. Mark which ones the learner already holds, from the probe map.
3. Draw the dependency graph as a Mermaid `graph TD`. Unconditional truths at the roots. The goal at the sink. Few nodes, short labels.
4. Stress-test each root. If it derives from something simpler that the learner accepts, push it down and extend the graph.
5. Decide Socratic or expository for each stretch.
6. Write `## Plan` in your reply: the approach in prose, then the Mermaid graph. The hook mirrors it to the note. Set `status: teaching` in the frontmatter.
7. Stop. Wait for the learner to approve the plan. Do not teach before that.

## Phase 3: Teach

Teach from the first missed bite of each strand onward, in the same bite size as the probe. For every node, foundation or derived:

1. **Motivate.** Why this node, now. What problem it solves.
2. **Establish.** A foundation: state it plainly, no caveats. A derived step: build it from what is already established, and answer "how could I have discovered this?". When a Socratic step has a right answer, ask it as a graded question.
3. **Connect.** Make the edge to the earlier nodes explicit.
4. **Check.** One pointed free-text question, or one multiple-choice question. If the learner misses, fix the node before you build on it.

Do not front-load all the foundations and then stop checking. A new foundation in the middle of the lesson goes through the same four steps.

Write math in LaTeX. Inline: `$f(x)$`. Display: `$$` on its own lines.

## Phase 4: End

The lesson ends when the learner says so, or when the sink node passes its check.

1. Append `## Weak spots` to the note: one line per gap that stayed shaky, in the form `<today>: <short phrase>`. If none, write `<today>: clean`.
2. Ask one question: "What should the loop do differently next time?" Append the answer under `## Retro`. This list is the queue of edits to this skill.
3. Set `status: done` in the frontmatter.
4. Score the lesson 0 to 5 with the scale in `quiz-rules.md`, from the Phase 3 checks.
5. Look in the SRS folder for a stub whose `target` matches the topic. If one exists, update `last_reviewed`, `next_due`, `interval`, `ease`, and `last_score`, append the new weak-spot line, and keep only the last 3 `weak_spots` entries, newest last. If none exists, create this file:

   ```yaml
   ---
   tags:
     - review/srs
   type: note
   target: "[[<Source note or lesson note>]]"
   last_reviewed: <today>
   next_due: <today + SRS first interval>
   interval: <SRS first interval>
   ease: <SRS first ease>
   last_score: <score>
   weak_spots:
     - "<today>: <short phrase>"
   ---

   Review stub for [[<Topic>]]. Made by the teach skill. Managed by the spaced-recall-tutor skill.
   ```

   Set `target` to the `1-Notes` source note that Phase 0 found. If Phase 0 found no note, set it to the lesson note.

6. Delete `~/.config/lesson-log`, `~/.config/lesson-log.cursor`, and `~/.config/lesson-log.session`. The hook is now off.
