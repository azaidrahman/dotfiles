#!/bin/bash
# Generates help text + app-launch rules from scripts/help-text.yaml, then runs goku.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$DIR/scripts/generate-help.py" "$DIR"
echo "Updated karabiner.edn"
goku
