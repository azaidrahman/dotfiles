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

# Window-level options that mobile-link-menu.sh copies onto a borrowed window.
# Unset them before unlinking so the shared window reverts to its normal
# (desktop) styling once it leaves mobile. Keep in sync with mobile-link-menu.sh.
STRIP_OPTS="window-style window-active-style pane-border-status pane-border-style pane-active-border-style"

tmux has-session -t "=$SESSION" 2>/dev/null || exit 0

mapfile -t borrowed < <(
  tmux list-windows -t "=$SESSION" -F '#{window_linked} #{window_index}' \
    | awk '$1 == 1 { print $2 }'
)

for idx in "${borrowed[@]}"; do
  for opt in $STRIP_OPTS; do
    tmux set -uw -t "$SESSION:$idx" "$opt" 2>/dev/null || true
  done
  tmux unlink-window -t "$SESSION:$idx" 2>/dev/null || true
done

exit 0
