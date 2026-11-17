# Fathom Reef

A cozy VR underwater reef full of cute fish for Meta Quest, plus a robot gym where little neural networks learn to walk. The whole thing was built in one evening by Claude (Claude Code) running in Termux **on the headset itself**, from Jazzy's dictated requests.

- **Read how it was made:** the full session transcript, with every command Claude ran unfolding like in the terminal: https://drakfyre.github.io/fathom-reef/
- **Play the flat version in your browser:** https://drakfyre.github.io/fathom-reef/play/
- **Downloads:** [Releases](https://github.com/drakfyre/fathom-reef/releases/latest)

## What's in it

| | |
|---|---|
| **Reef** | Fog-blue water, caustic light on the sand, kelp, corals, anemones, light shafts, bubbles and marine snow. 115 procedural fish in 5 species with flocking, curiosity, food chasing and scaring. All sound is synthesized in code. |
| **Live link** | A tiny local server (`127.0.0.1:34960`) that lets Claude compile and add new GDScript to the running app, post steps to an in-world build log, inspect values, and move files (`tools/reef-link`). The book and the robots below were built this way while Jazzy was inside the app. |
| **The book** | 13 illustrated pages on how deep neural networks work. In VR you pinch a page with the trigger and drag it, and the paper bends as it turns. |
| **Robot gym** | Dog-sized four-legged spider tanks and 1.7 m humanoids. Each has a small neural network (sensors → 16 hidden neurons → motor targets) trained by evolution. Two gyms run side by side with different scoring rules. Training is saved and resumes. |
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

Godot 4.7.2, Compatibility renderer. `./build.sh` makes the Quest APK without Gradle: Godot exports, then apktool adds the Khronos OpenXR loader and the Quest manifest entries. `./build-phone.sh` makes the phone APK. The Web, Windows, Linux and macOS presets are in `game/export_presets.cfg`.

`tools/make_transcript_page.py` turns a Claude Code session file into `docs/`.

## Credits

Made with [Godot Engine](https://godotengine.org) (MIT). The Quest APK bundles the Khronos OpenXR loader for Android (Apache-2.0). All art, sound and text in the app were generated in code for this project.
