#!/data/data/com.termux/files/usr/bin/bash
# Builds reefgym.apk: the phone (non-VR) version. Copies the live robot/book scripts into
# game/phone/ first so the phone ships exactly what runs in the headset.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p game/phone build
cp live/robots.gd live/book.gd game/phone/
echo "[1/3] Exporting from Godot"
rm -f build/phone.apk
godot --headless --path game --export-release Phone ../build/phone.apk 2>&1 | grep -E 'ERROR|rror:' | grep -v daemon || true
[ -f build/phone.apk ] || { echo "Godot export failed" >&2; exit 1; }
echo "[2/3] Aligning"
zipalign -f -p 4 build/phone.apk build/phone-aligned.apk
echo "[3/3] Signing"
apksigner sign --ks debug.keystore --ks-pass pass:android --key-pass pass:android --out reefgym.apk build/phone-aligned.apk
rm -f reefgym.apk.idsig
echo "built $(pwd)/reefgym.apk ($(du -h reefgym.apk | cut -f1))"
