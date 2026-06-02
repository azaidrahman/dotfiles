#!/usr/bin/env bash
# Fork the current branch into a new worktree + tmux pane running `claude`.
# Branch name = <current-branch>-<random id>. Current pane/checkout untouched.
#
# Usage: branch-pane.sh [v]    # pass "v" for a vertical (below) split; default horizontal
set -euo pipefail

# 1. Must be inside tmux
if [ -z "${TMUX:-}" ]; then
  echo "branch-pane: not inside tmux — nothing to do." >&2
  exit 1
fi

# 2. Resolve repo + names
REPO=$(git rev-parse --show-toplevel)
CUR=$(git rev-parse --abbrev-ref HEAD)
ID=$(( RANDOM % 9000 + 1000 ))          # 4-digit random id
BRANCH="${CUR}-${ID}"
WTNAME="${BRANCH//\//-}"                 # flatten slashes for the dir name
WT="${REPO}/.worktrees/${WTNAME}"

# 3. Bail (don't force) if it somehow already exists
if git show-ref --verify --quiet "refs/heads/${BRANCH}" || [ -e "$WT" ]; then
  echo "branch-pane: ${BRANCH} or ${WT} already exists — aborting." >&2
  exit 1
fi

# 4. Create the worktree off current HEAD
git worktree add -b "$BRANCH" "$WT" >/dev/null

# 5. Open a new pane (unfocused), launch claude in the worktree
SPLIT="-h"; [ "${1:-}" = "v" ] && SPLIT="-v"
NEW=$(tmux split-window "$SPLIT" -d -c "$WT" -P -F '#{pane_id}')
tmux send-keys -t "$NEW" "claude" Enter
tmux select-pane -t "$NEW" -T "$BRANCH"

# 6. Report
printf 'Branch   : %s\nWorktree : %s\nPane     : %s (claude starting)\n' "$BRANCH" "$WT" "$NEW"
