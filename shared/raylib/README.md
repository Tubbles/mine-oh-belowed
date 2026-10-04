# raylib binding and library

The Odin binding for raylib 6.0 with a raylib built from source, used through the `shared` collection (`build.sh` passes `-collection:shared=shared`, the game imports `shared:raylib` and `shared:raylib/rlgl`). Work item 0085.

Why a copy: the binding names its library by a path next to itself (`linux/libraylib.a`, and `../linux/libraylib.a` in `rlgl`), so no linker flag can swap in another archive. The toolchain under `~/opt/odin` stays untouched.

- `raylib.odin`, `raymath.odin`, `rlgl/rlgl.odin`, `LICENSE`: copied from `vendor/raylib/` of Odin release dev-2026-09 (nightly a2fb372). `raymath.odin` and `LICENSE` are unchanged. `raylib.odin` and `rlgl/rlgl.odin` carry one patch (work item 0113): a branch `when ODIN_OS == .Linux && ODIN_PLATFORM_SUBTARGET == .Android` ahead of the Linux one, importing `android/libraylib.a` (`../android/libraylib.a` in `rlgl`) with `system:log`, `system:android`, `system:EGL`, `system:GLESv3` and `system:OpenSLES`. The Linux lines stay byte for byte, since the nix flake's `substituteInPlace --replace-fail` patterns match them. `raymath.odin` belongs to package `raylib` and the game uses it. `easings.odin` and `raygui.odin` (which needs its own `libraygui.a`) are not copied.
- `platform.odin`: ours. Declares GLFW's `glfwGetPlatform`, `glfwGetCurrentContext`, `glfwGetWindowSize` and `glfwGetProcAddress` from the same archive, which the binding does not expose. The Android archive has no GLFW, so on Android the declarations are left out (a call from the game fails at compile time, not at link time) while the file still imports `android/libraylib.a`; that import and `core:c` carry `@(require)`, since nothing in the file uses them there and `-vet` refuses an unused import.
- `linux/libraylib.a`: written by `tools/build_raylib.sh`, GLFW with both the Wayland and the X11 backend. It is committed, so a checkout builds without cmake or a container.
- `android/libraylib.a`: written by `tools/build_raylib.sh --android` (work item 0113), raylib for Android arm64-v8a at API level 28 with OpenGL ES 3.0, `rcore_android.c` with `android_main` and the NDK's `android_native_app_glue.c` inside, no GLFW. Three source patches before cmake, each failing when its text is not found exactly as expected ([doc/android.md](../../doc/android.md), raylib for Android): the script rewrites `precision mediump float;` to `precision highp float;` in the two OpenGL ES3 default shaders of `rlLoadShaderDefault` (`src/rlgl.h`, work item 0126), since 16 bit mediump on Mali snaps everything drawn through raylib's batch (held block, models, particles) to a coarse world space grid that shifts with the camera; bounds the key branch's `keyPressedQueue` append in `AndroidInputCallback` (`src/platforms/rcore_android.c`, 0133); and rewrites that callback's gamepad key block into the form of upstream PR #5824 so a key event carrying the KEYBOARD source bit beside the GAMEPAD one (every button of a GameSir X2) is routed by its keycode instead of refused (0236). The NDK compiles with `-g` even in Release, so the script copies it through `llvm-strip --strip-debug`. Committed like the Linux archive.
- `windows/raylib.lib`: the static MSVC library (GLFW inside) from raylib's own release, for the Windows build (work item 0102). Not built here: taken unchanged from the release asset `raylib-6.0_win64_msvc16.zip` (https://github.com/raysan5/raylib/releases/download/6.0/raylib-6.0_win64_msvc16.zip, release page https://github.com/raysan5/raylib/releases/tag/6.0, zip SHA-256 `c93c7dc74576e00e3ee57fa2bd5fd109fbfc5aca87e12046dd7ec2c2268b3f78`), its `lib/raylib.lib`, 5297172 bytes, SHA-256 `e979fda995ea6b4ac0162156c6bc5d44c1ef6d995941f648a4f05ee19f3e00cb`. The Odin release dev-2026-09 for Windows ships the same bytes in `vendor/raylib/windows/raylib.lib`. The binding's Windows import already names `windows/raylib.lib`; `platform.odin` picks it on Windows.

After an Odin upgrade: copy `raylib.odin`, `raymath.odin`, `rlgl/rlgl.odin` and `LICENSE` from the new `vendor/raylib/` again and put the Android branch back into the two binding files, check the raylib version it binds, and when the version changed set `raylib_tag` in `tools/build_raylib.sh` and rerun it (plain and with `--android`), and replace `windows/raylib.lib` with the new release's `lib/raylib.lib` and its record above. The nix flake patches the three `.odin` files to link the system raylib and GLFW, so a renamed foreign import line breaks its `substituteInPlace` loudly.

## Build record

Rewritten by `tools/build_raylib.sh`: each platform's block runs from its marker to the next marker or the end, and a build rewrites only its own.

<!-- build record -->
- raylib tag: 6.0 (https://github.com/raysan5/raylib), commit dbc56a87da87d973a9c5baa4e7438a9d20121d28
- cmake flags: -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF -DPLATFORM=Desktop -DGLFW_BUILD_WAYLAND=ON -DGLFW_BUILD_X11=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
- compiler: cc (GCC) 16.2.1 20260819 (Red Hat 16.2.1-2)
- built: 2026-09-28T16:24Z
- archive: linux/libraylib.a, 3390886 bytes
<!-- android build record -->
- android raylib tag: 6.0 (https://github.com/raysan5/raylib), commit dbc56a87da87d973a9c5baa4e7438a9d20121d28
- android source patch: src/rlgl.h, the two OpenGL ES3 default shader lines "precision mediump float;" become "precision highp float;" (work item 0126)
- android source patch: src/platforms/rcore_android.c, the key branch's keyPressedQueue append is bounded by MAX_KEY_PRESSED_QUEUE as on the desktop (work item 0133)
- android source patch: src/platforms/rcore_android.c, the gamepad key block of AndroidInputCallback routes by keycode instead of refusing events with the KEYBOARD source bit, as upstream PR #5824 (work item 0236)
- android cmake flags: -G "Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=<ndk>/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28 -DPLATFORM=Android -DOPENGL_VERSION="ES 3.0" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF
- android compiler: NDK 27.3.13750724, Android (13691557, +pgo, +bolt, +lto, +mlgo, based on r522817d) clang version 18.0.4 (https://android.googlesource.com/toolchain/llvm-project d8003a456d14a3deb8054cdaa529ffbf02d9b262)
- android built: 2026-10-04T19:12Z
- android archive: android/libraylib.a, 2550222 bytes after llvm-strip --strip-debug
