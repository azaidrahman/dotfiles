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

mapfile -t borrowed < <(
  tmux list-windows -t "=$SESSION" -F '#{window_linked} #{window_index}' \
    | awk '$1 == 1 { print $2 }'
)

for idx in "${borrowed[@]}"; do
  tmux unlink-window -t "$SESSION:$idx" 2>/dev/null || true
done

exit 0
