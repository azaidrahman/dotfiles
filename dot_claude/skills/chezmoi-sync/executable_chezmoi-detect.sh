#!/usr/bin/env bash
# chezmoi-detect.sh — read-only detect + scan for chezmoi-sync.
#
# Reports uncommitted source changes, diverged targets, and flags anything that needs
# human eyes (secrets, private_ files) BEFORE the agent reconciles or commits. Mutates
# NOTHING — no `chezmoi add`, no `chezmoi apply`, no git writes. Reconcile (modify_/.tmpl
# handling) and commit/push stay in the skill, where the judgment and confirmation live.
#
# stdout: key: value report + listings
# Exit:   0  nothing to sync (both source and targets clean)
#        10  changes detected, no warnings
#        11  changes detected WITH warnings (secrets / private_) — agent must scrutinize
#         2  precondition failure (chezmoi missing / source not a repo)
set -euo pipefail

SRC="$HOME/.local/share/chezmoi"
command -v chezmoi >/dev/null 2>&1 || { echo "stop: chezmoi not installed" >&2; exit 2; }
git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "stop: $SRC is not a git repo" >&2; exit 2; }

echo "source: $SRC"

SRC_STATUS=$(git -C "$SRC" status --porcelain || true)
TGT_DIFF=$(chezmoi diff --no-pager 2>/dev/null || true)

if [ -z "$SRC_STATUS" ] && [ -z "$TGT_DIFF" ]; then
  echo "status: clean"
  echo "nothing to sync"
  exit 0
fi
echo "status: changes"

# Changed source file paths (porcelain col 4+), for scanning.
CHANGED=$(printf '%s\n' "$SRC_STATUS" | sed 's/^...//' | grep -v '^$' || true)

WARN=""
# private_ files in the changeset deserve extra scrutiny.
PRIV=$(printf '%s\n' "$CHANGED" | grep -E '(^|/)(private_|encrypted_)' || true)
[ -n "$PRIV" ] && WARN="${WARN}private_/encrypted_ files in changeset\n"

# Heuristic secret scan over BOTH pending surfaces: the source working diff and the
# diverged-target diff (where changes live before they're reconciled into source).
# Look only at added (+) lines so removals don't trip it.
SECRET_HITS=$( { git -C "$SRC" diff -- . 2>/dev/null; printf '%s\n' "$TGT_DIFF"; } \
  | grep -E '^\+' \
  | grep -Ei '(api[_-]?key|secret|token|password|passwd|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|xox[baprs]-)' \
  || true)
[ -n "$SECRET_HITS" ] && WARN="${WARN}possible secrets in added lines\n"

echo "--- source changes (git status) ---"
printf '%s\n' "$SRC_STATUS"
if [ -n "$TGT_DIFF" ]; then
  echo "--- diverged targets (chezmoi diff headers) ---"
  printf '%s\n' "$TGT_DIFF" | grep -E '^diff |^--- |^\+\+\+ ' || printf '%s\n' "$TGT_DIFF" | head -20
fi

if [ -n "$WARN" ]; then
  echo "--- WARNINGS (resolve before push) ---"
  printf "$WARN"
  [ -n "$PRIV" ] && { echo "private_/encrypted_:"; printf '%s\n' "$PRIV"; }
  [ -n "$SECRET_HITS" ] && { echo "secret-pattern added lines:"; printf '%s\n' "$SECRET_HITS" | head -20; }
  exit 11
fi
exit 10
