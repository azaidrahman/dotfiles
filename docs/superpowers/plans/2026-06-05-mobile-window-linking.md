# Mobile Window Linking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From inside the stripped `mobile` tmux session, pull any window from another session in on demand via a phone-friendly popup, and auto-clean those borrowed windows on detach.

**Architecture:** Two plain bash scripts in `~/.tmux/scripts/` (chezmoi source `dot_tmux/scripts/executable_*.sh`) plus three lines appended to `dot_tmux/conf.d/visual-mobile.conf`. `mobile-link-menu.sh` builds a native `display-menu` of candidate windows and links the chosen one into mobile (auto-selecting it). `mobile-unlink-all.sh` unlinks every borrowed (cross-session-linked) window from mobile. A `prefix+b` binding, a `client-attached` reminder toast, and a `client-detached` cleanup hook wire it together — all sourced only via `mobile-attach.sh`, so desktop config is untouched.

**Tech Stack:** bash, tmux 3.6a (`display-menu`, `link-window`/`unlink-window`, `#{window_linked}` format, session-scoped `set-hook`), chezmoi.

**Testing approach:** The scripts are tested against the live tmux server using **throwaway** sessions (`__lt_home`, `__lt_mobile`) so real sessions are never touched. Both scripts honour a `MOBILE_SESSION` env override (default `mobile`) purely so tests can target a throwaway session; production callers set nothing and get `mobile`. `mobile-link-menu.sh` also honours `MOBILE_LINK_DRYRUN=1` to print its candidate list instead of rendering the (interactive, untestable) menu. Tests run the chezmoi **source** files directly with `bash <path>` — identical content to what gets deployed — so no `chezmoi apply` is needed until the final integration task.

**Signing note:** This repo signs commits via an ssh-agent key that is NOT reachable from the agent sandbox (`SSH_AUTH_SOCK` unset, key is 1Password/agent-managed). Every commit step therefore uses `--no-gpg-sign`. After execution, the user can re-sign the batch in their live session, e.g. `git rebase --exec 'git commit --amend --no-edit -S' <base>`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `dot_tmux/scripts/executable_mobile-unlink-all.sh` | Cleanup: unlink borrowed windows from the mobile session |
| `dot_tmux/scripts/executable_mobile-link-menu.sh` | Picker: build + show the link popup; link chosen window into mobile |
| `dot_tmux/conf.d/visual-mobile.conf` | Wiring: `prefix+b` binding, attach toast, detach cleanup hook |

Work happens in `/Users/abdullahzaidas-sani/.local/share/chezmoi` on `main` (this repo's convention — every commit, including the sibling spec, lives on `main`).

---

### Task 1: Cleanup script (`mobile-unlink-all.sh`)

**Files:**
- Create: `dot_tmux/scripts/executable_mobile-unlink-all.sh`
- Test: ad-hoc on-server harness (commands below; nothing persisted)

- [ ] **Step 1: Write the failing test**

Save as `/tmp/test-unlink.sh`:

```bash
#!/usr/bin/env bash
# On-server test for mobile-unlink-all.sh using throwaway sessions.
set -u
SRC="$HOME/.local/share/chezmoi/dot_tmux/scripts/executable_mobile-unlink-all.sh"
S=__lt_mobile; H=__lt_home

cleanup() { tmux kill-session -t "=$S" 2>/dev/null; tmux kill-session -t "=$H" 2>/dev/null; }
trap cleanup EXIT
cleanup

tmux new-session -d -s "$S"            # $S:0 = mobile's own window
tmux new-session -d -s "$H"            # $H:0 = a "desktop" window
tmux link-window -d -s "$H:0" -t "$S:" # borrow $H:0 into $S (now linked)

before=$(tmux list-windows -t "=$S" -F x | wc -l | tr -d ' ')
MOBILE_SESSION="$S" bash "$SRC"
after=$(tmux list-windows -t "=$S" -F x | wc -l | tr -d ' ')
home=$(tmux list-windows -t "=$H" -F x | wc -l | tr -d ' ')

echo "before=$before after=$after home=$home"
if [ "$before" = 2 ] && [ "$after" = 1 ] && [ "$home" = 1 ]; then
  echo PASS
else
  echo FAIL; exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/test-unlink.sh`
Expected: FAIL — `bash: .../executable_mobile-unlink-all.sh: No such file or directory`, and `after=2` (nothing was unlinked).

- [ ] **Step 3: Write minimal implementation**

Create `dot_tmux/scripts/executable_mobile-unlink-all.sh`:

```bash
#!/usr/bin/env bash
# Unlink every borrowed (cross-session-linked) window from the mobile session,
# leaving mobile's own windows intact. Run from the `client-detached` hook so
# the mobile session is pristine on the next connect.
#
# A window with #{window_linked}=1 lives in more than one session, i.e. it was
# borrowed in via mobile-link-menu.sh. unlink-window (no -k) only removes the
# mobile linkage; it can never orphan or kill a window that exists elsewhere.
set -u

SESSION="${MOBILE_SESSION:-mobile}"

tmux has-session -t "=$SESSION" 2>/dev/null || exit 0

borrowed=$(tmux list-windows -t "=$SESSION" -F '#{window_linked} #{window_index}' \
  | awk '$1 == 1 { print $2 }')

for idx in $borrowed; do
  tmux unlink-window -t "$SESSION:$idx"
done

exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/test-unlink.sh`
Expected: `before=2 after=1 home=1` then `PASS`.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/executable_mobile-unlink-all.sh
git commit --no-gpg-sign -m "feat(tmux): mobile-unlink-all.sh — clear borrowed windows from mobile"
```

---

### Task 2: Picker script (`mobile-link-menu.sh`)

**Files:**
- Create: `dot_tmux/scripts/executable_mobile-link-menu.sh`
- Test: ad-hoc on-server harness against the dry-run path (commands below)

- [ ] **Step 1: Write the failing test**

Save as `/tmp/test-linkmenu.sh`:

```bash
#!/usr/bin/env bash
# Test the candidate-filtering of mobile-link-menu.sh via its dry-run mode.
# A window in another session must be offered; mobile's own window must not.
set -u
SRC="$HOME/.local/share/chezmoi/dot_tmux/scripts/executable_mobile-link-menu.sh"
S=__lt_mobile; H=__lt_home

cleanup() { tmux kill-session -t "=$S" 2>/dev/null; tmux kill-session -t "=$H" 2>/dev/null; }
trap cleanup EXIT
cleanup

tmux new-session -d -s "$S"
tmux new-session -d -s "$H"
own_id=$(tmux list-windows -t "=$S" -F '#{window_id}')
home_id=$(tmux list-windows -t "=$H" -F '#{window_id}')

out=$(MOBILE_SESSION="$S" MOBILE_LINK_DRYRUN=1 bash "$SRC" "")
echo "--- dry-run output ---"; echo "$out"; echo "----------------------"

ok=1
echo "$out" | cut -f1 | grep -qx "$home_id"  || { echo "MISS: home window not offered"; ok=0; }
echo "$out" | cut -f1 | grep -qx "$own_id"   && { echo "BUG: mobile's own window offered"; ok=0; }
[ "$ok" = 1 ] && echo PASS || { echo FAIL; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/test-linkmenu.sh`
Expected: FAIL — `bash: .../executable_mobile-link-menu.sh: No such file or directory`, empty dry-run output, `MISS: home window not offered`.

- [ ] **Step 3: Write minimal implementation**

Create `dot_tmux/scripts/executable_mobile-link-menu.sh`:

```bash
#!/usr/bin/env bash
# Show a popup menu of windows from OTHER sessions that can be linked into the
# mobile session. Selecting an item links that real, live window into mobile and
# (no -d on link-window) jumps onto it. Bound to prefix+b in visual-mobile.conf,
# which passes the triggering client so display-menu knows where to draw.
#
#   arg1                = triggering client name (#{client_name})
#   MOBILE_SESSION      = target session (default: mobile)
#   MOBILE_LINK_DRYRUN  = if set, print "<window_id>\t<label>" candidates and
#                         exit instead of showing the menu (for tests)
set -u

CLIENT="${1:-}"
SESSION="${MOBILE_SESSION:-mobile}"

# Window-ids already in mobile (its own + already-borrowed), newline separated.
in_mobile=$(tmux list-windows -t "=$SESSION" -F '#{window_id}' 2>/dev/null)

# Candidate windows across all sessions, most-recently-active first.
# Columns: activity \t window_id \t session \t index \t name \t command
candidates=$(tmux list-windows -a -F \
  '#{window_activity}	#{window_id}	#{session_name}	#{window_index}	#{window_name}	#{pane_current_command}' \
  | sort -t$'\t' -k1,1nr \
  | cut -f2-)

dry="${MOBILE_LINK_DRYRUN:-}"
items=()
count=0
while IFS=$'\t' read -r wid sess idx name cmd; do
  [ -z "$wid" ] && continue
  printf '%s\n' "$in_mobile" | grep -qx "$wid" && continue   # skip windows in mobile
  label="$sess:$idx  $name ($cmd)"
  if [ -n "$dry" ]; then
    printf '%s\t%s\n' "$wid" "$label"
    continue
  fi
  key=""
  if [ "$count" -lt 9 ]; then key=$((count + 1)); fi
  items+=("$label" "$key" "link-window -s $wid -t $SESSION:")
  count=$((count + 1))
done <<< "$candidates"

[ -n "$dry" ] && exit 0

if [ "${#items[@]}" -eq 0 ]; then
  tmux display-message "No other windows to link"
  exit 0
fi

tmux display-menu -c "$CLIENT" -T " Link window → $SESSION " -x C -y C "${items[@]}"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/test-linkmenu.sh`
Expected: dry-run output lists the `__lt_home:0` row (its window-id, then label), does NOT list mobile's own window-id, then `PASS`.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/executable_mobile-link-menu.sh
git commit --no-gpg-sign -m "feat(tmux): mobile-link-menu.sh — popup to link windows into mobile"
```

---

### Task 3: Wire the binding and hooks into `visual-mobile.conf`

**Files:**
- Modify: `dot_tmux/conf.d/visual-mobile.conf` (append at end of file)

- [ ] **Step 1: Append the wiring block**

Append these lines to the end of `dot_tmux/conf.d/visual-mobile.conf`:

```tmux

# --- Window linking (phone-friendly): pull real windows into mobile on demand ---
# prefix+b opens a popup of windows from other sessions; selecting one links it
# into mobile and jumps onto it. Borrowed windows are auto-unlinked on detach so
# mobile is pristine on the next connect. The binding passes the triggering
# client so display-menu knows where to draw. See
# docs/superpowers/specs/2026-06-05-mobile-window-linking-design.md
bind b run-shell "~/.tmux/scripts/mobile-link-menu.sh '#{client_name}'"
set-hook -t mobile client-attached 'display-message -d 2500 "  prefix+b → link a window  "'
set-hook -t mobile client-detached 'run-shell "~/.tmux/scripts/mobile-unlink-all.sh"'
```

- [ ] **Step 2: Verify the fragment still parses standalone**

The fragment is scoped to the `mobile` session, so source it the same way `mobile-attach.sh` does. Ensure a `mobile` session exists, then source the source-tree copy directly:

Run:
```bash
tmux has-session -t '=mobile' 2>/dev/null || tmux new-session -d -s mobile
tmux source-file ~/.local/share/chezmoi/dot_tmux/conf.d/visual-mobile.conf && echo "SOURCED OK"
```
Expected: `SOURCED OK` with no tmux parse errors.

- [ ] **Step 3: Verify the binding and hooks registered**

Run:
```bash
echo "--- binding ---"; tmux list-keys -T prefix | grep mobile-link-menu
echo "--- hooks ---"; tmux show-hooks -t '=mobile' | grep -E 'client-attached|client-detached'
```
Expected: one `bind-key … b … mobile-link-menu.sh` line; and `client-attached`/`client-detached` hooks naming the toast and `mobile-unlink-all.sh`.

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/conf.d/visual-mobile.conf
git commit --no-gpg-sign -m "feat(tmux): wire prefix+b link picker + auto-clean into mobile session"
```

---

### Task 4: Deploy and verify end-to-end (manual)

**Files:** none (deploy + manual verification per the spec's Verification section)

- [ ] **Step 1: Deploy with chezmoi**

Run:
```bash
chezmoi diff   # review: two new scripts + visual-mobile.conf change only
chezmoi apply
ls -l ~/.tmux/scripts/mobile-link-menu.sh ~/.tmux/scripts/mobile-unlink-all.sh
```
Expected: `chezmoi diff` shows only the three intended changes; after apply both scripts exist at `~/.tmux/scripts/` and are executable (`-rwxr-xr-x`, from the `executable_` prefix).

- [ ] **Step 2: Toast on attach**

From a desktop client, in a spare pane: `tmux attach -t mobile` (or trigger `mobile-attach.sh`).
Expected: a `prefix+b → link a window` message appears in the status line for ~2.5s on attach.

- [ ] **Step 3: Picker lists other windows, links one in**

While attached to `mobile`, press `C-space` then `b`.
Expected: a centred popup titled `Link window → mobile` lists windows from your other live sessions (e.g. `costs:0`, `iris:1`, `trudax:0`), most-recent first, with number shortcuts `1`–`9`. It does NOT list mobile's own window.
Tap a number. Expected: that real window appears inside `mobile` (stripped chrome) and you are jumped onto it.

Confirm the source is untouched:
```bash
tmux list-windows -t '=<home-session>'   # the window still exists in its home session
```

- [ ] **Step 4: Multiple links + switching**

`prefix+b` again, pick a second window. Expected: both borrowed windows are now in mobile; `C-space n` / `C-space p` cycle between them and mobile's own shell.

- [ ] **Step 5: Auto-clean on detach**

Detach (`C-space d`), then reattach: `tmux attach -t mobile`.
Expected: `mobile` is back to only its own shell window; the borrowed windows are gone from mobile but still alive in their home sessions:
```bash
tmux list-windows -t '=mobile'        # only mobile's own window
tmux list-windows -t '=<home>'        # borrowed window still present
```

- [ ] **Step 6: Desktop unaffected**

Attach a desktop session (e.g. `tmux attach -t costs`).
Expected: full desktop visuals unchanged — the feature touched nothing outside the mobile path.

- [ ] **Step 7 (optional): clean up test artifacts**

```bash
rm -f /tmp/test-unlink.sh /tmp/test-linkmenu.sh
tmux kill-session -t '=__lt_mobile' 2>/dev/null; tmux kill-session -t '=__lt_home' 2>/dev/null; true
```

---

## Notes for the executor

- **Known limitation (continuum):** if tmux-continuum snapshots while borrowed windows are linked into mobile, a restore may recreate them as separate windows rather than links. Out of scope per the spec; do not try to solve it.
- **`prefix+b` is global** once `visual-mobile.conf` has been sourced (first mobile-attach). Harmless — it always targets `mobile` — and survives `prefix+r`. Do not move it into `keys.conf`; isolation in the mobile path is intentional.
- Do **not** push. Committing only, per the user's request; the user's chezmoi-sync flow carries it up later.
