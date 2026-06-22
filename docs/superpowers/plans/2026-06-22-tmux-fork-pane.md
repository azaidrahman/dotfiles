# tmux-native Claude session fork (`|` / `_`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `branch-pane` Claude skill with two tmux bindings (`|`, `_`) that fork the Claude conversation in the currently selected pane into a new pane, with no Claude turn consumed.

**Architecture:** A single chezmoi-managed shell script (`fork-claude-pane.sh`) is invoked by two tmux `run-shell` bindings. tmux expands `#{pane_id}`/`#{pane_current_path}`/`#{pane_tty}` into args. The script gates to Claude panes, resolves the session id from the pane's cwd (newest `.jsonl` by mtime — no `$CLAUDE_CODE_SESSION_ID` available externally), splits a detached pane, and resumes a forked session in it. The old skill (chezmoi-managed) is removed from the chezmoi source.

**Tech Stack:** bash, tmux, chezmoi.

## Global Constraints

- Everything is chezmoi-managed: edit files under `~/.local/share/chezmoi/` (the source), then `chezmoi apply`. Never edit `~/.tmux/...` or `~/.claude/...` targets directly.
- Executable scripts use the `executable_` source-name prefix so chezmoi sets the exec bit.
- tmux scripts live in `dot_tmux/scripts/` and are referenced at runtime as `~/.tmux/scripts/<name>`.
- Bindings live in `dot_tmux/conf.d/keys.conf`.
- Reload tmux config with `tmux source-file ~/.tmux.conf` (bound to `prefix r`).
- Commit messages end with the Co-Authored-By trailer used in this repo's history.

---

### Task 1: Create the fork script

**Files:**
- Create: `dot_tmux/scripts/executable_fork-claude-pane.sh`

**Interfaces:**
- Consumes: invoked as `fork-claude-pane.sh <pane_id> <cwd> <tty> <h|v>`.
- Produces: a new tmux pane running `claude --resume <id> --fork-session`; user-facing status via `tmux display-message`. Exit 0 in all branches (a failed gate is not a tmux error).

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Fork the Claude *conversation* running in a given tmux pane into a new pane.
# Triggered by tmux bindings | (side-by-side) and _ (below). Runs OUTSIDE the
# Claude process, so $CLAUDE_CODE_SESSION_ID is unavailable — the session id is
# derived from the pane's cwd (newest session .jsonl by mtime).
#
# Args: 1=origin pane id  2=pane cwd  3=pane tty  4=split dir (h|v)
set -euo pipefail

PANE="${1:?pane id required}"
CWD="${2:?cwd required}"
TTY="${3:?tty required}"
DIR="${4:-h}"

# 1. Gate: the origin pane must be running a `claude` process.
tty="${TTY#/dev/}"
if [ -z "$tty" ] || ! ps -t "$tty" -o command= 2>/dev/null | grep -q '[c]laude'; then
  tmux display-message "fork: not a Claude pane"
  exit 0
fi

# 2. Resolve the session id from the cwd's project dir (newest .jsonl by mtime).
PROJ=$(printf '%s' "$CWD" | tr '/.' '--')
NEWEST=$(ls -t "$HOME/.claude/projects/${PROJ}/"*.jsonl 2>/dev/null | head -1 || true)
SID=$(basename "${NEWEST:-}" .jsonl)
if [ -z "$SID" ]; then
  tmux display-message "fork: no session for this dir"
  exit 0
fi

# 3. Split a detached pane from the origin and fork the session into it.
SPLIT="-h"; [ "$DIR" = "v" ] && SPLIT="-v"
NEW=$(tmux split-window "$SPLIT" -d -c "$CWD" -t "$PANE" -P -F '#{pane_id}')
tmux send-keys -t "$NEW" "claude --resume $SID --fork-session" Enter
tmux select-pane -t "$NEW" -T "fork:${SID:0:8}"

# 4. Report (no Claude relays output now).
tmux display-message "forked ${SID:0:8} → $NEW"
```

- [ ] **Step 2: Apply and verify it lands executable**

Run:
```bash
cd ~/.local/share/chezmoi && chezmoi apply && ls -l ~/.tmux/scripts/fork-claude-pane.sh
```
Expected: file exists with an `-rwx` (executable) mode.

- [ ] **Step 3: Shellcheck / syntax check**

Run: `bash -n ~/.tmux/scripts/fork-claude-pane.sh && echo OK`
Expected: `OK` (no syntax errors).

- [ ] **Step 4: Manual gate test from a non-Claude pane**

Run (from a plain shell pane, substituting that pane's real values is unnecessary — use current):
```bash
~/.tmux/scripts/fork-claude-pane.sh "$(tmux display -p '#{pane_id}')" "$PWD" "$(tmux display -p '#{pane_tty}')" h
```
Expected: a tmux status message `fork: not a Claude pane`, no new pane, exit 0.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/executable_fork-claude-pane.sh
git commit -m "feat(tmux): fork-claude-pane script (resolve session from pane cwd)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Add the `|` and `_` bindings

**Files:**
- Modify: `dot_tmux/conf.d/keys.conf` (after the `\` / `-` split binds, lines ~21-23)

**Interfaces:**
- Consumes: `dot_tmux/scripts/executable_fork-claude-pane.sh` from Task 1 (runtime path `~/.tmux/scripts/fork-claude-pane.sh`).
- Produces: prefix `|` and prefix `_` bindings.

- [ ] **Step 1: Add the bindings**

Insert immediately after the `bind - split-window -v ...` line:

```
# Fork the Claude session in the current pane (shift the split key)
bind | run-shell "~/.tmux/scripts/fork-claude-pane.sh '#{pane_id}' '#{pane_current_path}' '#{pane_tty}' h"
bind _ run-shell "~/.tmux/scripts/fork-claude-pane.sh '#{pane_id}' '#{pane_current_path}' '#{pane_tty}' v"
```

- [ ] **Step 2: Apply and reload tmux config**

Run:
```bash
cd ~/.local/share/chezmoi && chezmoi apply && tmux source-file ~/.tmux.conf && echo reloaded
```
Expected: `reloaded`, no errors.

- [ ] **Step 3: Verify bindings are registered**

Run: `tmux list-keys -T prefix | grep -E "fork-claude-pane"`
Expected: two lines — one for `|`, one for `_`.

- [ ] **Step 4: Manual end-to-end test**

From a pane running `claude`, press `prefix |`. Expected: a new side-by-side pane opens running `claude --resume <id> --fork-session`, a status message `forked <id> → %N` appears, and the origin pane is untouched. Repeat with `prefix _` for a below split.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/conf.d/keys.conf
git commit -m "feat(tmux): bind | and _ to fork the current Claude pane

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Remove the branch-pane skill

**Files:**
- Delete (chezmoi source): `dot_claude/skills/branch-pane/SKILL.md`, `dot_claude/skills/branch-pane/executable_branch-pane.sh`

**Interfaces:**
- Consumes: nothing. The bindings from Task 2 fully replace this skill.
- Produces: removal of `~/.claude/skills/branch-pane/` after apply.

- [ ] **Step 1: Remove the source directory**

Run:
```bash
cd ~/.local/share/chezmoi && git rm -r dot_claude/skills/branch-pane
```
Expected: both `SKILL.md` and `executable_branch-pane.sh` removed.

- [ ] **Step 2: Apply so the target is removed**

Run:
```bash
chezmoi apply && ls ~/.claude/skills/branch-pane 2>&1 || echo "gone"
```
Expected: `gone` (directory no longer exists). If chezmoi leaves the empty dir, `rmdir ~/.claude/skills/branch-pane`.

- [ ] **Step 3: Confirm no dangling references**

Run: `grep -rn "branch-pane" ~/.local/share/chezmoi --include='*.md' --include='*.sh' --include='*.conf' | grep -v docs/superpowers`
Expected: no output (the only remaining mentions are in the spec/plan docs).

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git commit -m "chore(claude): remove branch-pane skill (replaced by tmux | / _ binds)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Bindings `|`/`_` → Task 2. ✓
- Script with gate + cwd-based session resolution + split/fork + feedback → Task 1. ✓
- Skill deletion (via chezmoi source, since it's managed) → Task 3. ✓
- Out-of-scope items (start-ticket, plain split binds) — untouched. ✓

**Placeholder scan:** No TBD/TODO; all code and commands are concrete. ✓

**Type consistency:** Arg order `pane_id cwd tty {h|v}` is identical in the script header (Task 1), the bindings (Task 2), and the manual test command. Runtime script path `~/.tmux/scripts/fork-claude-pane.sh` is consistent across tasks. ✓
