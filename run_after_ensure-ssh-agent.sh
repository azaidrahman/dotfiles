#!/bin/sh
# Ensure the per-login session ssh-agent LaunchAgent is actually loaded.
#
# When com.zaid.ssh-agent isn't loaded, ~/.cache/ssh/agent.sock never appears,
# yet .zshenv still exports SSH_AUTH_SOCK to it — so every non-SSH shell points
# at a socket that doesn't exist and `ssh-keygen -Y sign` fails the commit with
# "Couldn't get agent socket". Idempotent; runs on every `chezmoi apply`.
set -eu

plist="$HOME/Library/LaunchAgents/com.zaid.ssh-agent.plist"
[ -f "$plist" ] || exit 0

domain="gui/$(id -u)"
launchctl print "$domain/com.zaid.ssh-agent" >/dev/null 2>&1 && exit 0

launchctl bootstrap "$domain" "$plist" 2>/dev/null ||
  echo "warning: could not bootstrap com.zaid.ssh-agent" >&2
