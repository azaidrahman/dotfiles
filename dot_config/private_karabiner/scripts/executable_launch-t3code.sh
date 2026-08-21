#!/bin/sh
# Launch T3 Code with Bitbucket credentials in its environment.
#
# `export` in a shell never reaches apps launched via `open -a` — only
# `launchctl setenv` propagates into the GUI/launchd domain apps inherit.
# T3 Code reads T3CODE_BITBUCKET_EMAIL / T3CODE_BITBUCKET_API_TOKEN, so push
# them there each time before opening it.
. "$HOME/.config/zsh/secrets.zsh"

launchctl setenv T3CODE_BITBUCKET_EMAIL "$T3CODE_BITBUCKET_EMAIL"
launchctl setenv T3CODE_BITBUCKET_API_TOKEN "$T3CODE_BITBUCKET_API_TOKEN"

open -a "T3 Code (Alpha)"
