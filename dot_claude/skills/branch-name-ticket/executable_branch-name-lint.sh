#!/usr/bin/env bash
# branch-name-lint.sh — classify the current branch against <type>/<KEY>-<slug>, and
# perform the deterministic, no-Jira-needed normalization (uppercase key, keep slug).
#
# Does NOT find tickets (tmux/Jira), squeeze summaries, or touch the remote — those need
# judgment / confirmation and stay in the skill. The only mutation it makes is a LOCAL
# `git branch -m`, which is always safe and reversible; pass --dry-run to suppress even that.
#
# Usage:  branch-name-lint.sh [--dry-run]
# stdout: status: <state> + details (and the rename if performed)
# Exit:   0  ok (already valid) OR normalized successfully
#         3  no ticket key present        → skill finds the ticket (tmux/commits/Jira)
#         4  key present but no valid type → skill picks the type from content
#         2  protected/detached/not a repo
set -euo pipefail

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "stop: not inside a git repo"; exit 2; }
BR=$(git branch --show-current)
[ -n "$BR" ] || { echo "stop: detached HEAD"; exit 2; }
case "$BR" in
  main|master|develop) echo "status: protected ($BR) — never rename"; exit 2 ;;
esac

TYPES='feat|fix|chore|docs|refactor|test|ci|build'

# Already canonical?  <type>/<UPPERKEY>-...
if printf '%s' "$BR" | grep -qE "^($TYPES)/[A-Z]+-[0-9]+(-.*)?$"; then
  echo "status: ok"
  echo "branch: $BR"
  exit 0
fi

# Any ticket key at all?
if ! printf '%s' "$BR" | grep -qiE '[A-Z]+-[0-9]+'; then
  echo "status: no-key"
  echo "branch: $BR"
  echo "next: find the ticket (tmux window / commits / Jira), then rename"
  exit 3
fi

KEY=$(printf '%s' "$BR" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]')
TYPE=${BR%%/*}
REST=${BR#*/}

# Valid type prefix present and the key lives in the tail → deterministic case/format fix.
if printf '%s' "$BR" | grep -qE "^($TYPES)/" && [ "$TYPE" != "$BR" ]; then
  # Uppercase the key inside the tail, leave the rest of the slug untouched.
  NORM_REST=$(printf '%s' "$REST" | sed -E "s/[A-Za-z]+-[0-9]+/$KEY/")
  NEW="$TYPE/$NORM_REST"
  if [ "$NEW" = "$BR" ]; then
    echo "status: ok"; echo "branch: $BR"; exit 0
  fi
  echo "status: normalizable"
  echo "from: $BR"
  echo "to:   $NEW"
  if [ "$DRY" -eq 1 ]; then
    echo "dry-run: would rename locally to '$NEW'"
  else
    # Case-only rename collides on macOS's case-insensitive FS ("already exists");
    # go through a temp name. This is the common case (lowercase key → uppercase).
    if [ "$(printf '%s' "$NEW" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$BR" | tr 'A-Z' 'a-z')" ]; then
      git branch -m "${BR}-caserename-tmp"
      git branch -m "$NEW"
    else
      git branch -m "$NEW"
    fi
    echo "renamed (local): $NEW"
    echo "note: remote rename (if pushed) + open-PR check stay in the skill"
  fi
  exit 0
fi

# Key present but no recognized <type>/ prefix → needs a type decision.
echo "status: needs-type"
echo "branch: $BR"
echo "key: $KEY"
echo "slug: $(printf '%s' "$REST" | sed -E "s/[A-Za-z]+-[0-9]+-?//")"
echo "next: skill picks <type> ($TYPES) from branch content, then renames to <type>/$KEY-<slug>"
exit 4
