#!/data/data/com.termux/files/usr/bin/bash
# Pulls the robot training from Reef Gym Trainer on a PC (same Wi-Fi) into the "built-in" training
# that the web/phone/desktop builds offer as "Continue Fathom's training".
# usage: tools/pull-from-pc.sh <pc ip> <6-digit code shown in the trainer>
# Then rebuild with ./build-flat.sh and publish.
set -euo pipefail
cd "$(dirname "$0")/.."
IP=${1:?PC IP address (shown at the top of the trainer)}
CODE=${2:?6-digit link code (shown at the top of the trainer)}
for n in robots robots_v2; do
  REEF_HOST=$IP REEF_TOKEN=$CODE tools/reef-link get "user://$n.json" "game/phone/seed_$n.json" >/dev/null
done
REEF_HOST=$IP REEF_TOKEN=$CODE tools/reef-link log "Training copied to Fathom for the built-in version." >/dev/null
python3 -I -c '
import json
for n in ("robots", "robots_v2"):
    d = json.load(open(f"game/phone/seed_{n}.json"))
    print(n, {k: (v["gen"], round(v["record"], 2), len(v.get("timeline", []))) for k, v in d.items() if isinstance(v, dict)}, "(gen, record m, timeline snapshots)")'
