# 0126: High precision in raylib's default shader on Android

Status: todo

## Goal

The user, on the phone (version code 222, 2026-09-30): "all player movement and camera movement moves some voxels around in a jarring way, like if I hold a block in my hand and look around, each of the 6 corner voxels of the block randomly moves ever so slightly on each frame that the camera moves, producing a skewed block when I stop the camera movement."

Cause, confirmed in the raylib 6.0 source (`tmp/raylib-src/src/rlgl.h`, `rlLoadShaderDefault`): the default vertex and fragment shaders for OpenGL ES 3 declare `precision mediump float;` (lines 5021 to 5022 and 5074 to 5075, kept for WebGL browsers). On Mali, mediump is 16 bit: world space vertex positions near 200 blocks have a spacing of 0.125, so everything drawn through raylib's batch or the default shader (the arm and the held block in `render_player.odin`, models, particles, billboards, loose items, entities, flames, weather, icons: every file `grep -l 'rlgl.Begin\|rl.Draw' src/*.odin` lists) snaps to that grid, differently each frame as the camera moves, and the held cube's corners end up on different grid points. The game's own shaders (`data/shaders/`) already get `precision highp float; precision highp int;` from `shader_source_for_gles` (`render_chunks.odin`), which is why the chunks do not do it. OpenGL ES 3.0 guarantees highp in both shader stages.

## Change

- `tools/build_raylib.sh`, the Android build (`android_configure_and_build`): before cmake, rewrite the two ES3 default shader blocks of the cloned `src/rlgl.h` from `precision mediump float;` to `precision highp float;` with a `sed` that fails loudly when the pattern is not found (so a raylib upgrade that moves the text is noticed), then build as today and copy the archive to `shared/raylib/android/libraylib.a`. The Linux and Windows builds are untouched (desktop GL has no precision qualifiers).
- Rebuild the archive in the container (`tools/build_raylib.sh --android`) and commit it. Check with `strings shared/raylib/android/libraylib.a | grep -c 'precision highp float'` (at least 2) and `grep -c 'precision mediump float'` (the ES2 blocks may remain, since the archive is built for ES3 only; say what you find).
- `shared/raylib/README.md`: the Android archive's record names the patch. `doc/build.md` (Android toolchain, the `tools/build_raylib.sh --android` bullet): the patch and why. `doc/log/<date>.md`: the symptom, the cause and the decision.

## Verify

- `./build.sh check-android` and `./build.sh android` (the APK links against the new archive).
- The user, on the phone: a held block keeps its shape while looking around; particles and models no longer jitter.
