---
name: revamp-chat
description: Use when the current conversation is messy, off-track, or the user wants to restart with a clear plan - reads a prompt, writes a structured plan, and prepares a handoff to a new session
---

# Revamp Chat

Restart a conversation with clarity. Analyze a prompt, write a structured plan, and hand off to a fresh session.

## Workflow

### 1. Capture the Prompt

If the user provided a prompt as args to `/revamp-chat`, use it directly. Otherwise, ask:

> What would you like the new chat to accomplish?

Also scan the current conversation for useful context: decisions made, files touched, errors hit, partial progress worth keeping.

### 2. Write the Plan

Generate a filename using this format: `{short-title}_{YYYY_MM_DD-HHMMPM}.md`
- `{short-title}`: a very short kebab-case summary of the plan (2-4 words, e.g. `k8s-deploy`, `auth-refactor`, `fix-logging`)
- Date/time: use `date +%Y_%m_%d-%I%M%p` to get the format like `2026_03_12-0530PM`

Example: `k8s-deploy_2026_03_12-0530PM.md`

Save the plan to `~/.claude/plans/{filename}` using this structure:

```markdown
# Plan: {descriptive title}

## Original Prompt
> {the user's prompt, verbatim}

## Context
What we're trying to accomplish and why.
Include relevant decisions or context carried over from the previous session.

## Current State
What exists now - files modified, partial work done, known issues.
Reference specific file paths and line numbers where relevant.

## Steps

### Step 1: {title}
- What to do (be specific - file paths, function names, commands)
- Expected outcome
- Files involved

### Step 2: {title}
...

## Constraints
- Requirements, limitations, or preferences noted
- Tech stack, patterns to follow, things to avoid

## Verification
How to confirm the plan succeeded (tests to run, behavior to check).
```

**Plan quality rules:**
- Be specific - reference actual file paths, function names, error messages
- Carry forward useful context from the current conversation
- Each step should be independently actionable
- Never write vague steps like "implement the feature"

### 3. Show the Plan

Display the full plan to the user so they can review it before switching sessions.

### 4. Provide the Handoff Prompt

After showing the plan, tell the user:

```
Plan saved to ~/.claude/plans/revamp-{filename}.md

Run /new to start a fresh session, then paste this:

Read and follow the plan at ~/.claude/plans/revamp-{filename}.md step by step. After reading, confirm your understanding of each step before starting.
```

Format the paste-able prompt as a single fenced code block so it's easy to copy.

## Do NOT

- Modify or delete any existing files
- Skip showing the plan to the user before handoff
- Write vague or generic steps
- Include conversation-internal noise that isn't relevant to the plan
