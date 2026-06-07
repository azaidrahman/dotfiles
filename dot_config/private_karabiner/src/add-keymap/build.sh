#!/bin/bash
# Compile the add-keymap wizard into the committed binary.
# Run this after changing any Go source here.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
go build -o ../../scripts/executable_add-keymap .
echo "Built scripts/executable_add-keymap"
