#!/bin/bash
# Save this machine's Karabiner device settings to chezmoi.
# Splits entries into:
#   - devices_apple.json  (shared across all machines — Apple keyboards)
#   - devices_<host>.json (machine-specific — everything else)
#
# Run after configuring devices in the Karabiner UI.
# Usage: ./save-devices.sh
set -euo pipefail

HOSTNAME=$(hostname -s)
CHEZMOI_DIR="$(chezmoi source-path)"
APPLE_OUT="$CHEZMOI_DIR/dot_config/private_karabiner/data/devices_apple.json"
HOST_OUT="$CHEZMOI_DIR/dot_config/private_karabiner/data/devices_${HOSTNAME}.json"
KARABINER_JSON="$HOME/.config/karabiner/karabiner.json"

python3 - "$KARABINER_JSON" "$APPLE_OUT" "$HOST_OUT" <<'PYEOF'
import json, sys

karabiner_path, apple_path, host_path = sys.argv[1], sys.argv[2], sys.argv[3]

APPLE_VENDOR_ID = 1452  # Apple Inc.

def is_apple(d):
    ids = d.get("identifiers", {})
    vid = ids.get("vendor_id")
    if vid == APPLE_VENDOR_ID:
        return True
    # Fallback: no vendor_id + uses apple_vendor_* key codes
    if vid is None:
        blob = json.dumps(d)
        if "apple_vendor_" in blob:
            return True
    return False

with open(karabiner_path) as f:
    k = json.load(f)

devices = []
for p in k.get("profiles", []):
    if p.get("name") == "Zaid":
        devices = p.get("devices", [])
        break

apple = [d for d in devices if is_apple(d)]
host = [d for d in devices if not is_apple(d)]

with open(apple_path, "w") as f:
    json.dump(apple, f, indent=4)
    f.write("\n")

with open(host_path, "w") as f:
    json.dump(host, f, indent=4)
    f.write("\n")

print(f"Apple (shared):  {len(apple)} entries -> {apple_path}")
print(f"Host-specific:   {len(host)} entries -> {host_path}")
PYEOF

echo
echo "Next: cd $CHEZMOI_DIR && git add dot_config/private_karabiner/data/ && git commit -m 'karabiner: update device settings'"
