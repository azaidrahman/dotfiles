---
name: plan-audit
description: Use when starting or ending a work session to check superpowers plan status against actual codebase state, update completed checkboxes, and identify the next plan to execute
---

# Plan Audit

Reconcile superpowers plan checkboxes with actual codebase state. Update completion, identify what's next, prepare handoff.

## When to Use

- Starting a session — pick up where you left off
- Finishing work — mark progress before closing
- User asks about plan status or "what's next"

## Workflow

### 1. Discover Plans

```bash
ls -1t docs/superpowers/plans/*.md
```

### 2. Audit Each Plan

For each plan, read it and extract:
- **Goal** (from header)
- **Tasks** (checkbox items `- [ ]` / `- [x]`)
- **Key files** mentioned in each task

Then verify each unchecked task against reality:
- `git log --oneline --all -- <file>` — was this file committed?
- Check if files/resources the task creates actually exist
- Check if configs/registry YAML the task adds are present

**Classify each plan:**

| Status | Meaning |
|--------|---------|
| `done` | All deliverables verified in codebase (even if boxes unchecked) |
| `partial` | Some tasks done, some remaining |
| `not-started` | No deliverables found in codebase |
| `superseded` | A newer plan covers the same scope |
| `blocked` | Depends on another incomplete plan |

### 3. Update Plan Files

For tasks verified as complete but still unchecked:
- Edit `- [ ]` to `- [x]` in the plan file
- Do NOT change any other plan content

If the entire plan is done, add to the top (below frontmatter if any):

```markdown
> **Status: COMPLETED** — All tasks verified against codebase on {date}.
```

### 4. Output Status Report

Print a summary table to the conversation:

```
## Plan Status — {date}

### Done
| Plan | Date | Summary |
|------|------|---------|

### In Progress
| Plan | Done/Total | Next Task | Blocker |
|------|------------|-----------|---------|

### Not Started
| Plan | Summary | Depends On |
|------|---------|------------|

### Superseded
| Plan | Replaced By |
|------|-------------|
```

### 5. Recommend Next Plan

Pick the next plan based on:
1. **Dependencies** — blocked plans go last
2. **Foundation first** — infra/tooling before features
3. **Momentum** — partially-done plans before fresh ones

Output:

```
## Next Plan

**File:** docs/superpowers/plans/{filename}
**Goal:** {one-line goal}
**Why next:** {reasoning}

To execute in a new session, paste:

    Read and execute the plan at docs/superpowers/plans/{filename} using superpowers:executing-plans. Start by reading the plan and confirming your understanding.
```

## Rules

- Never delete plan files — they're project history
- Never modify plan content beyond checking boxes and adding status line
- Never execute plan tasks — that's for executing-plans
- Never create new plans — that's for writing-plans
- Use parallel agents to audit multiple plans simultaneously when there are many
