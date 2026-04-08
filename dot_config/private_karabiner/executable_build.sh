#!/bin/bash
# Build karabiner config: merge layers, generate from YAMLs.
#
# Usage: ./build.sh
#
# After building, deploy and compile:
#   chezmoi apply && goku
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# 1. Merge base + layers → karabiner.edn
sed '/;; {{LAYERS}}/{
r layers.edn
d
}' karabiner.base.edn > karabiner.edn

# 2. Generate help text + rules from config/*.yaml
uv run scripts/generate.py "$DIR"

echo "Done. Now run: chezmoi apply && goku"
