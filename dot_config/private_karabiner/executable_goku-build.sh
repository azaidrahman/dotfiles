#!/bin/bash
# Merges karabiner.base.edn + layers.edn → karabiner.edn, then runs goku.
# Edit karabiner.base.edn and layers.edn, not karabiner.edn directly.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

sed '/;; {{LAYERS}}/{
r layers.edn
d
}' karabiner.base.edn > karabiner.edn

goku
