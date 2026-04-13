#!/bin/bash
# Save this machine's Karabiner device settings to chezmoi.
# Run after configuring devices in the Karabiner UI.
#
# Usage: ./save-devices.sh
set -euo pipefail

HOSTNAME=$(hostname -s)
CHEZMOI_DIR="$(chezmoi source-path)"
OUT="$CHEZMOI_DIR/dot_config/private_karabiner/data/devices_${HOSTNAME}.json"
KARABINER_JSON="$HOME/.config/karabiner/karabiner.json"

python3 - "$KARABINER_JSON" "$OUT" <<'PYEOF'
import json, sys

karabiner_path, out_path = sys.argv[1], sys.argv[2]

with open(karabiner_path) as f:
    k = json.load(f)

devices = []
for p in k.get("profiles", []):
    if p.get("name") == "Zaid":
        devices = p.get("devices", [])
        break

with open(out_path, "w") as f:
    json.dump(devices, f, indent=2)
    f.write("\n")
PYEOF

echo "Saved $(hostname -s) device settings -> $OUT"
echo "Next: cd $CHEZMOI_DIR && git add dot_config/private_karabiner/data/devices_${HOSTNAME}.json && git commit -m 'karabiner: save $(hostname -s) device settings'"
