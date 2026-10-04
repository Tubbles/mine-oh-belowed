# 0236: Gamepad buttons on Android reach the game

Status: verified (2026-10-04, done by the main agent as trivia (a build script patch mirroring upstream, the archive rebuilt, the docs), the patch tested on a 6.0 clone and the archive built, the phone the user's; from the user on the phone with the GameSir X2: "Only the crosshair on the gamesir works, i remember having basically the same issue with my other repo sleipner, could you check out what we did there? It might've been an upstream raylib bug?"; it is: raylib 6.0's Android input callback drops every gamepad key event that also carries the keyboard source bit, which the GameSir X2 sets on every event, so only the stick axes (motion events) arrive; sleipner carries the same fix as a raylib patch, `recipes/raylib/patches/0001-android-trust-keycode-not-source-bits.patch`, and upstream fixed it after 6.0 in raysan5/raylib PR #5824, merged 2026-05-10 as a005a044d, not in a tagged release)

## Goal

Every button of a clip controller on the phone reaches the game: `AndroidInputCallback` routes a key event with a gamepad or joystick source bit by its keycode (a recognised gamepad keycode is a gamepad button, anything else falls through to the keyboard handler) instead of refusing the whole event when the keyboard source bit is set too.

## Controls

No binding changes. The raylib backend's gamepad on Android works as on the desktop once the events arrive.

## Change

- `tools/build_raylib.sh`: a third Android source patch beside the precision and the key queue ones, `patch_android_gamepad_source_bits`, which rewrites the gamepad key block of `AndroidInputCallback` in `src/platforms/rcore_android.c` into the form of upstream PR #5824 (the `!FLAG_IS_SET(source, AINPUT_SOURCE_KEYBOARD)` guard gone; `AndroidTranslateGamepadButton(keycode)` decides; an unknown keycode falls through to the keyboard handler, which also keeps a phone's volume keys, which arrive with the gamepad bit set, out of the gamepad path, the bug the 6.0 guard was added for). The script fails unless it finds the 6.0 block once, so a raylib upgrade that absorbs the fix is noticed; the build record in `shared/raylib/README.md` names the patch.
- `shared/raylib/android/libraylib.a` rebuilt with `tools/build_raylib.sh --android` and committed.
- Docs: `shared/raylib/README.md` (the Android archive's patches, three now), `doc/android.md` (raylib for Android, the patches list), `doc/log/2026-10-04.md`.

## Verify

- `tools/build_raylib.sh --android` builds (the patch rewrites exactly one block), `./build.sh check-android`, `./build.sh android`.
- The phone with the GameSir X2: the face buttons, the D-pad, the bumpers and the sticks all act; the HUD's F3 Input page shows the presses.
- When raylib ships a release with PR #5824, the patch fails to find the block: drop it and its record line.
