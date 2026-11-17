#!/data/data/com.termux/files/usr/bin/bash
# Builds fathomreef.apk (Quest / OpenXR) without Gradle:
#   1. Godot exports the game (Android release template, unsigned)
#   2. apktool adds the Khronos OpenXR loader (.so) and the XR manifest entries
#   3. zipalign + apksigner with a local debug key (debug.keystore, not in git)
# Needs: godot 4.7.2 + Android export templates, apktool, zipalign, apksigner, curl.
set -euo pipefail
cd "$(dirname "$0")"
# No arguments: build both the public APK (live link off) and the dev APK (live link on, with the
# secret from game/link_token.txt). With arguments: ./build.sh <preset> <output.apk>
if [ $# -eq 0 ]; then
  "$0" Quest fathomreef.apk
  [ -f game/link_token.txt ] && "$0" "Quest Dev" fathomreef-dev.apk
  exit 0
fi
PRESET=$1
OUT=$2
LOADER_VER=1.1.65
LOADER_DIR=third_party/openxr_loader
step() { printf '\n[%s/4] %s\n' "$1" "$2"; }

step 1 "Fetching the OpenXR loader (if needed)"
if [ ! -f "$LOADER_DIR/aar/jni/arm64-v8a/libopenxr_loader.so" ]; then
  mkdir -p "$LOADER_DIR"
  curl -sfL -o "$LOADER_DIR/loader.aar" \
    "https://repo1.maven.org/maven2/org/khronos/openxr/openxr_loader_for_android/$LOADER_VER/openxr_loader_for_android-$LOADER_VER.aar"
  unzip -o -q "$LOADER_DIR/loader.aar" -d "$LOADER_DIR/aar"
fi

step 2 "Exporting from Godot"
rm -rf build && mkdir -p build
godot --headless --path game --export-release "$PRESET" ../build/godot.apk 2>&1 \
  | grep -E 'ERROR|rror:' | grep -v daemon || true
[ -f build/godot.apk ] || { echo "Godot export failed" >&2; exit 1; }

step 3 "Adding OpenXR loader + manifest entries"
apktool d -f -s build/godot.apk -o build/dec >/dev/null
mkdir -p build/dec/lib/arm64-v8a
cp "$LOADER_DIR/aar/jni/arm64-v8a/libopenxr_loader.so" build/dec/lib/arm64-v8a/
python3 -I tools/patch_manifest.py build/dec/AndroidManifest.xml
# Godot's template declares mipmap/themed_icon as an alias apktool can't rebuild
if grep -q 'name="themed_icon" format="string"' build/dec/res/values-anydpi-v26/mipmaps.xml 2>/dev/null; then
  cp build/dec/res/mipmap-anydpi-v26/icon.xml build/dec/res/mipmap-anydpi-v26/themed_icon.xml
  rm build/dec/res/values-anydpi-v26/mipmaps.xml
fi
apktool b build/dec -o build/unsigned.apk >/dev/null
zipalign -f -p 4 build/unsigned.apk build/aligned.apk

step 4 "Signing"
[ -f debug.keystore ] || keytool -genkeypair -keystore debug.keystore -storepass android -keypass android \
  -alias debug -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Fathom Reef Debug" >/dev/null
apksigner sign --ks debug.keystore --ks-pass pass:android --key-pass pass:android \
  --out "$OUT" build/aligned.apk
rm -f "$OUT.idsig"
echo "built $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
