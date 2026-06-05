# Mobile Window Linking — Design

**Date:** 2026-06-05
**Status:** Approved

## Problem

The `mobile` tmux session (Termius / small iOS screens) renders with a stripped,
ASCII-only visual profile scoped via `set -t mobile …` in `visual-mobile.conf`.
That strip is **per-session**, but the thing doing the rendering is the tmux
**client**, and tmux has no client scope — option values are shared by every
client attached to a session. Consequence: a session created on the desktop
(`costs`, `iris`, `trudax`, …) keeps its full desktop visuals no matter which
device views it. From the phone you can only get the stripped look by *being in
the `mobile` session* — but then mobile is just its own empty shell, with no way
to reach the work running in other sessions.

`switch-client` to another session is not a fix: it lands you on that session,
which carries the full desktop chrome (powerline, Ghostty-tuned `window-style`,
the teal background artifact) — the exact problem the mobile strip exists to
avoid.

## Goals

1. From inside `mobile`, pull any window from any other session **into** mobile
   on demand, so the **mobile session's** stripped chrome wraps it.
2. Phone-friendly selection: a native popup with one-tap number keys, no
   external dependency, no fuzzy-search TUI.
3. Keep `mobile` pristine: borrowed windows are cleaned up automatically on
   detach, leaving their home sessions untouched.
4. The reminder for how to invoke it is surfaced on connect, since the binding
   is easy to forget on a phone used infrequently.

## Non-goals

- Per-client rendering of styles/colours/borders. tmux cannot scope those to a
  client; this design works *with* the session-scope model rather than against
  it.
- Live pane previews in the picker (that was the television-channel option,
  passed over in favour of a lighter native menu).
- Touching desktop config. Nothing in this feature loads unless you go mobile.
- Solving the simultaneous phone-and-desktop case (see Known limitations).

## Behaviour / flow

1. Phone connects → Termius sets `LC_MOBILE=1` → `mobile-attach.sh` creates the
   `mobile` session if absent, sources `visual-mobile.conf`, and attaches. You
   land on mobile's own zsh window. A 2.5s toast reminds you: `prefix+b → link a
   window`.
2. `prefix+b` opens a centred `display-menu` listing every window from your
   *other* sessions, most-recently-active first, with number-key shortcuts.
3. Selecting an item links that real, live window into `mobile` and jumps you
   onto it — same process, same scrollback, now rendered inside the stripped
   mobile session.
4. Repeat to gather more windows; switch between them with normal `prefix+n` /
   `prefix+<number>`.
5. On detach (explicit or a Termius drop), the borrowed windows are unlinked
   from `mobile`. They stay alive and unchanged in their home sessions. Mobile
   is pristine for the next connect.

## Architecture

All three pieces are part of the mobile feature; the desktop config is
untouched.

| File | Change | Role |
|------|--------|------|
| `dot_tmux/scripts/executable_mobile-link-menu.sh` | new | Builds and shows the picker |
| `dot_tmux/scripts/executable_mobile-unlink-all.sh` | new | Detach cleanup |
| `dot_tmux/conf.d/visual-mobile.conf` | +3 lines | Binding + attach toast + detach hook |

### `mobile-link-menu.sh` — the picker

- Argument: the triggering client name (passed by the binding as
  `#{client_name}`).
- Collect the set of window-ids already in `mobile`
  (`tmux list-windows -t '=mobile' -F '#{window_id}'`).
- Read `tmux list-windows -a -F '#{window_id}\t#{session_name}\t#{window_index}\t#{window_name}\t#{pane_current_command}'`,
  **excluding** any window whose id is already in `mobile` (this skips both
  mobile's own windows and windows already borrowed in). Sort most-recently
  active first (mirror the ordering idiom in `tv-tmux-windows.sh`:
  `#{session_last_attached}` / activity).
- Build `display-menu` items: label `"<session>:<idx>  <name> (<cmd>)"`,
  shortcut keys `1`–`9` for the first nine entries (the rest remain
  arrow-selectable with no shortcut), command
  `run-shell '~/.tmux/scripts/mobile-link-menu.sh borrow <window_id>'`.
- **Borrow mode** (`mobile-link-menu.sh borrow <window_id>`): `link-window`s the
  window into `mobile` (no `-d`, so it **auto-selects** and you jump onto it),
  then strips its window-level styling — see the styling note below.
- Render with an explicit client target:
  `tmux display-menu -c "$client" -T ' Link window → mobile ' -x C -y C "${items[@]}"`.
- Empty list → `tmux display-message 'No other windows to link'` and exit 0.

**Client targeting is the load-bearing mechanic.** A `display-menu` invoked from
a script spawned by `run-shell` has no inherent client to draw on. The binding
passes the triggering client via `#{client_name}` (expanded by tmux at
invocation time, with the triggering client's context) and the script forwards
it with `display-menu -c`. Without this, the menu fails to render or targets the
wrong client.

**Window-scoped styling is the second load-bearing mechanic.** The status bar is
a *session* option, so mobile's stripped status line wraps any window
automatically. But `window-style`/`window-active-style` (the pane background) and
`pane-border-status`/`pane-border-style`/`pane-active-border-style` (borders +
the title bar) are *window* options with **no session scope** — `set -t mobile
window-style …` only sets the *current* window, which is why visual-mobile.conf's
strip historically applied only to mobile's own window 0. A window linked in from
the desktop therefore keeps inheriting the **global** desktop theme (the teal
`window-style`, the `pane-border-status bottom` title bar). Borrow mode fixes
this by copying these options (`STRIP_OPTS`) from mobile's own (unlinked) window
onto the freshly-linked window.

### `mobile-unlink-all.sh` — cleanup

- Exit 0 if `mobile` does not exist.
- For each window in `mobile` where `#{window_linked}` is `1`, run
  `tmux unlink-window -t 'mobile:<idx>'`.
- `window_linked` is `0` for mobile's own shell (it lives in one session) and
  `1` for any borrowed window (linked across sessions). So the predicate is
  borrowed-only by construction: it never touches mobile's own window. Plain
  `unlink-window` (no `-k`) refuses to destroy a window's last link, so a
  borrowed window is only removed from `mobile` and never orphaned or killed in
  its home session.
- Before unlinking each borrowed window, **unset** its `STRIP_OPTS` window
  options (`set -uw`). Because window options are shared across a link, borrow
  mode's strip also restyled the window in its home session; unsetting reverts it
  to the global desktop styling once it leaves `mobile`. (Same `STRIP_OPTS` list
  as `mobile-link-menu.sh` — kept in sync by comment.)

### `visual-mobile.conf` additions

```tmux
# Link a real window from another session into mobile (phone-friendly popup).
bind b run-shell "~/.tmux/scripts/mobile-link-menu.sh '#{client_name}'"

# Remind how to link on connect; clear borrowed windows on detach.
set-hook -t mobile client-attached 'display-message -d 2500 "  prefix+b → link a window  "'
set-hook -t mobile client-detached 'run-shell "~/.tmux/scripts/mobile-unlink-all.sh"'
```

These load via `mobile-attach.sh` sourcing `visual-mobile.conf`, so they exist
only once you have gone mobile in a server's lifetime — exactly when they are
needed.

## Known limitations

- **`prefix+b` becomes a global binding** once `visual-mobile.conf` has been
  sourced (first mobile-attach). It is harmless elsewhere — it always targets
  `mobile` — and it survives `prefix+r` because no fragment unbinds it.
- **No previews** in the menu; labels only (consequence of the native-menu
  choice over television).
- **Continuum/resurrect**: if a snapshot is taken while borrowed windows are
  linked into `mobile`, a later restore may recreate them as separate windows
  rather than links. Not solved here; the simultaneous phone-and-desktop case it
  depends on is out of scope.
- **Borrowed windows are restyled in their home session too** while linked in,
  because `window-style`/border options are shared across the link. They are
  restored on detach (unlink unsets them), so this is only visible if you view
  the same window on the desktop *while* it is borrowed — the out-of-scope
  simultaneous case. Assumes desktop windows use the **global** style (no
  per-window override); a window carrying its own per-window style would be
  reverted to global rather than to that custom style.

## Verification

1. `chezmoi apply`, then attach the `mobile` session from a desktop client.
   Confirm the `prefix+b → link a window` toast appears for ~2.5s on attach.
2. `prefix+b` → confirm the popup lists windows from other sessions (not
   mobile's own), most-recent first, with number-key shortcuts.
3. Pick one → confirm the real window appears inside `mobile` with the stripped
   chrome and you are jumped onto it. Confirm it still exists in its home
   session (`tmux list-windows -t '=<home>'`).
4. Link a second window; confirm `prefix+n` cycles between them.
5. Detach → reattach. Confirm `mobile` is back to just its own shell and the
   borrowed windows are intact in their home sessions.
6. Confirm desktop sessions are visually unchanged (the feature touched nothing
   outside the mobile path).
