#!/usr/bin/env bash
# SessionStart hook: if this Claude session runs in an unsettled tmux window,
# inject an instruction telling Claude to run the rename-tmux-window skill.
#
# Coordinates with ~/.claude/hooks/notify-tmux.sh, which owns window naming via
# two window options:
#   @claude_autoname_done — the name is settled (user named it, or it was already
#                           auto-named). The canonical "leave it alone" flag.
#   @claude_base          — the clean base name the glyph hook renders from.
# We skip if either is set, so we never clobber a manual rename or a prior
# auto-name. Survives resume/compact/clear (the options persist on the window).

set -euo pipefail

# Not in tmux → nothing to rename.
[ -n "${TMUX:-}" ] || exit 0

# T3 Code drives its own tmux window naming, and this pane may already carry
# a real name it set (e.g. a project name) that just isn't tracked via our
# @claude_base/@claude_autoname_done options. Don't nag to rename those.
if [ "${__CFBundleIdentifier:-}" = "com.t3tools.t3code" ] || env | grep -q '^T3CODE_'; then
    exit 0
fi

PANE="${TMUX_PANE:-}"

# Name already settled by notify-tmux.sh (manual or auto) → don't touch it.
# (Plain `if`, not `[ ] && exit` — under `set -e` a false test would abort the
# script before reaching the injection below.)
done_flag=$(tmux show-options -wqv -t "$PANE" @claude_autoname_done 2>/dev/null || true)
if [ -n "$done_flag" ]; then exit 0; fi

# Base already set by a prior session → don't clobber it.
base=$(tmux show-options -wqv -t "$PANE" @claude_base 2>/dev/null || true)
if [ -n "$base" ]; then exit 0; fi

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"This tmux window has not been named yet. Before responding to the user, invoke the rename-tmux-window skill to name the window after the current branch's Jira ticket and summary."}}
JSON
