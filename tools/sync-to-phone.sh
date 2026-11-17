#!/data/data/com.termux/files/usr/bin/bash
# Copies the robot training from the headset app (Fathom Reef, running) to the phone app (Reef Gym,
# running), through both live links.  usage: tools/sync-to-phone.sh <phone adb connect port> [phone ip]
# Order matters on the phone: remove the gyms BEFORE writing the saves, or a still-running gym
# finishes a round and overwrites the import (rounds end every second or two).
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=${1:?phone adb connect port (Settings > Developer options > Wireless debugging)}
IP=${2:-192.168.0.65}
OUT=game/phone
TMP=$(mktemp -d)
printf 'extends Node\nvar main\nfunc _ready():\n\tfor n in ["robots", "robots_v2"]:\n\t\tmain.set_meta("export_" + n, FileAccess.get_file_as_string("user://%%s.json" %% n))\n' > "$TMP/export.gd"
tools/reef-link run export "$TMP/export.gd" >/dev/null
for n in robots robots_v2; do
  tools/reef-link eval "get_meta(\"export_$n\")" | python3 -I -c 'import json,sys; r=json.load(sys.stdin); open(sys.argv[1],"w").write(json.loads(r["result"]))' "$OUT/seed_$n.json"
done
tools/reef-link rm export >/dev/null
tools/reef-link log "Robot training sent to the phone." >/dev/null
proot-distro login debian -- bash -c "
  adb connect $IP:$PORT >/dev/null && adb -s $IP:$PORT forward tcp:34961 tcp:34960 >/dev/null
  cd $PWD
  L='env REEF_PORT=34961 /data/data/com.termux/files/usr/bin/python3 -I tools/reef-link'
  \$L rm robots >/dev/null; \$L rm robots_v2 >/dev/null; sleep 1
  for n in robots robots_v2; do \$L put user://\$n.json $OUT/seed_\$n.json >/dev/null; done
  \$L run robots live/robots.gd >/dev/null && \$L run robots_v2 live/robots.gd >/dev/null
  \$L log 'Robot training received from Fathom.' >/dev/null
  for g in robots robots_v2; do echo \"phone \$g: spider gen \$(\$L eval \"link.live_root.get_node(\\\"\$g\\\").species[\\\"spider\\\"].gen\" | grep -o '[0-9]*\"}' | tr -d '\"}')\"; done
"
rm -rf "$TMP"
