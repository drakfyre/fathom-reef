# Fathom Reef

A cozy VR underwater reef full of cute fish for Meta Quest, plus a robot gym where little neural networks learn to walk. The whole thing was built in one evening by Claude (Claude Code) running in Termux **on the headset itself**, from Jazzy's dictated requests.

- **Read how it was made:** the full session transcript, with every command Claude ran unfolding like in the terminal: https://drakfyre.github.io/fathom-reef/
- **Play the flat version in your browser:** https://drakfyre.github.io/fathom-reef/play/
- **Downloads:** [Releases](https://github.com/drakfyre/fathom-reef/releases/latest)

## What's in it

| | |
|---|---|
| **Reef** | Fog-blue water, caustic light on the sand, kelp, corals, anemones, light shafts, bubbles and marine snow. 115 procedural fish in 5 species with flocking, curiosity, food chasing and scaring. All sound is synthesized in code. |
| **Live link** | A tiny local server (`127.0.0.1:34960`, off in published builds, see below) that lets Claude compile and add new GDScript to the running app, post steps to an in-world build log, inspect values, and move files (`tools/reef-link`). The book and the robots below were built this way while Jazzy was inside the app. |
| **The book** | 13 illustrated pages on how deep neural networks work. In VR you pinch a page with the trigger and drag it, and the paper bends as it turns. |
| **Robot gym** | Dog-sized four-legged spider tanks and 1.7 m humanoids. Each has a small neural network (sensors → 16 hidden neurons → motor targets) trained by evolution. Two gyms run side by side with different scoring rules. Training is saved and resumes. |
| **Evolution timeline** | Each gym saves its champion's network at generation 1, every 10th generation and on new records. A fifth stage replays up to five champions side by side, from the first to the latest. |
| **Start fresh or continue** | The flat versions ask on first launch: watch the robots learn from zero, or continue the training done on the headset. **Restart** wipes local training. |
| **Fast-forward** | Up to 4× training speed without making physics steps bigger: time scale and physics tick rate rise together, so every step stays 1/90 s. |

## Builds

| File | For |
|---|---|
| `fathomreef.apk` | Meta Quest 2/3/3S/Pro (VR). Sideload with developer mode, e.g. `adb install fathomreef.apk`. |
| `reefgym.apk` | Android phones (flat "Reef Gym"). |
| `ReefGym.exe` | Windows x86-64. Not code-signed, so SmartScreen may warn. |
| `ReefGym.x86_64` | Linux x86-64 (`chmod +x` first). |
| `ReefGym.zip` | macOS (universal, ad-hoc signed). First launch: right-click → Open. |

The desktop, phone and web builds are the flat version: the reef, both robot gyms, fast-forward and the book as a two-page reader. Drag to orbit, scroll or pinch to zoom.

VR controls: left stick swim; right stick turn / rise and sink; trigger sprinkles fish food; grip blows bubbles; A/X calls the fish; B help; Y build log.

## Building

Godot 4.7.2, Compatibility renderer. `./build.sh` makes the Quest APK without Gradle: Godot exports, then apktool adds the Khronos OpenXR loader and the Quest manifest entries. `./build-flat.sh` makes the phone APK and the Web, Windows, Linux and macOS builds (presets in `game/export_presets.cfg`). The `Trainer` preset is a Windows build whose live link listens on the local network, protected by a 6-digit code shown on screen; `tools/pull-from-pc.sh` copies its training into the built-in starting point.

`tools/make_transcript_page.py` turns a Claude Code session file into `docs/`.

## Live link (for developers)

The live link lets a tool on the same device (or, for the trainer, the same network) add code to the running app, read values and copy files. Because it can run code, it is **off in every published build**. It only starts when:

- you run the project from the Godot editor, or start an export with `--live-link`: a random 6-digit code is printed to the console (and shown on the build-log board in VR), or
- you export with the **Quest Dev** / **Phone Dev** presets after creating your own secret: `python3 -c 'import secrets; print(secrets.token_hex(16))' > game/link_token.txt` (git-ignored). `./build.sh` and `./build-phone.sh` then also make `*-dev.apk` with the link on, or
- you export the **Trainer** preset: it listens on the local network and shows a 6-digit code on screen.

Every request must include the code. `tools/reef-link` reads it from `REEF_TOKEN`, or from `game/link_token.txt`:

```
REEF_TOKEN=123456 tools/reef-link list
REEF_TOKEN=123456 tools/reef-link log "hello"
REEF_TOKEN=123456 tools/reef-link run mynode my_script.gd     # script extends Node/Node3D; may declare `var main`
REEF_HOST=192.168.1.20 REEF_TOKEN=123456 tools/reef-link get user://robots.json robots.json   # trainer on a PC
```

Anything that isn't a JSON object with the right code (for example an HTTP request a web page sends to localhost) closes the connection, and three wrong codes switch the link off until the app restarts.

## Credits

Made with [Godot Engine](https://godotengine.org) (MIT). The Quest APK bundles the Khronos OpenXR loader for Android (Apache-2.0). All art, sound and text in the app were generated in code for this project.
