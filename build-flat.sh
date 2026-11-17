#!/data/data/com.termux/files/usr/bin/bash
# Builds every non-VR version of Reef Gym from the same code:
#   reefgym.apk (Android), build/web (also copied to docs/play), build/win, build/linux, build/mac,
#   and build/trainer/ReefGymTrainer.exe (Windows, LAN link with an on-screen code, faster speeds).
# Copies the live robot/book/timeline scripts into game/phone/ first.
set -euo pipefail
cd "$(dirname "$0")"
cp live/robots.gd live/book.gd live/timeline.gd game/phone/
./build-phone.sh
for p in Web Windows Linux macOS Trainer; do
  out=$(sed -n "/^name=\"$p\"/,/^export_path/p" game/export_presets.cfg | grep export_path | cut -d'"' -f2)
  mkdir -p "game/$(dirname "$out")"
  echo "[$p] -> $out"
  (cd game && godot --headless --xr-mode off --path . --export-release "$p" "$out" 2>&1 | grep -E 'ERROR|rror:' | grep -v daemon || true)
done
rm -rf docs/play && cp -r build/web docs/play
ls -la reefgym.apk build/win build/linux build/mac build/trainer | grep -vE '^total|^d'
