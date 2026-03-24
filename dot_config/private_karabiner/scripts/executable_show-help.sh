#!/bin/bash
DIR="$(dirname "$0")"
killall help-hud 2>/dev/null
"$DIR/help-hud" "$DIR/$1.yaml" &
