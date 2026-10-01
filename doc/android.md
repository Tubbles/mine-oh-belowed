# Android app

The game as a native Android app (0114): the same `game` package built with Odin's android subtarget as `libmain.so` for arm64, driven by raylib's Android backend and packaged with `odin bundle android`. The build rules for agents are in [CLAUDE.md](../CLAUDE.md); the desktop build is in [build.md](build.md).

- `./build.sh check-android` checks the Android target on the host; `./build.sh android` builds the signed APK `build/android/mine-oh-belowed.apk`.
- Input is raylib's only, no SDL ([input.md](input.md), Android). Touch is the overlay ([touch_overlay.md](touch_overlay.md)).
- Android-only code lives in `#+build linux:android` files or behind `when ODIN_PLATFORM_SUBTARGET == .Android`; every GLFW call sits under `when ODIN_PLATFORM_SUBTARGET != .Android`, since `shared/raylib/platform.odin` declares none on Android and a stray call fails the check.

## Toolchain

The versions are the GitHub ubuntu-24.04 runner's, which ships them at `ANDROID_HOME=/usr/local/lib/android/sdk` with JDK 17.

| Part | Version |
|---|---|
| NDK | 27.3.13750724 |
| build-tools | 34.0.0 |
| platform | android-34 |
| Minimum API level | 28 (Android 9), `-minimum-os-version`; raylib's archive targets the same |

- `tools/android_env.sh`, sourced by the build scripts or a shell (`. tools/android_env.sh`), exports `ANDROID_NDK_VERSION`, `ANDROID_BUILD_TOOLS_VERSION`, `ANDROID_PLATFORM_VERSION`, `ANDROID_API_LEVEL`, `ODIN_ANDROID_SDK` (`$ODIN_ANDROID_SDK`, else `$ANDROID_HOME`, else `~/opt/android/sdk`) and `ODIN_ANDROID_NDK` (`$ODIN_ANDROID_SDK/ndk/<version>`), and puts build-tools and platform-tools on the `PATH`. CI uses the same file.
- `tools/android_toolchain.sh` installs the SDK under `${ODIN_ANDROID_SDK:-~/opt/android/sdk}`: the command line tools `commandlinetools-linux-15859902_latest.zip` (SHA-256 recorded in the script, checked before unpacking) into `cmdline-tools/latest/`, the licenses, then `platform-tools`, `build-tools;34.0.0`, `platforms;android-34` and `ndk;27.3.13750724` through `sdkmanager`. A re-run skips what is installed. The SDK takes 2.4 GB, mostly the NDK.
- `sdkmanager`, `apksigner` and `keytool` need Java, which Bazzite lacks, so by default the script runs inside the distrobox `mine-oh-belowed-android` (image `registry.fedoraproject.org/fedora-toolbox:44`, created on first use with `java-25-openjdk-headless cmake gcc gcc-c++ make git unzip`; Fedora 44 has no JDK 21). `--host` runs the steps on a machine with Java, curl and unzip. The home directory is shared, so the SDK lands under `~/opt` either way.
- Run the Odin and SDK steps inside the container on the couch: `apksigner` needs its Java, and the NDK runs there as well as on the host.

## raylib for Android

`tools/build_raylib.sh --android` runs `tools/android_toolchain.sh`, then builds in the same container (`--android --host` builds on this machine). It clones the raylib tag as for the desktop, applies two source patches, configures in `tmp/raylib-build-android/`, strips the archive with the NDK's `llvm-strip --strip-debug` into `shared/raylib/android/libraylib.a` (the NDK compiles with `-g` even in Release: 12.3 MB before, 2.6 MB after) and rewrites the Android build record in `shared/raylib/README.md`.

```
-G "Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=$ODIN_ANDROID_NDK/build/cmake/android.toolchain.cmake
-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28 -DPLATFORM=Android -DOPENGL_VERSION="ES 3.0"
-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF
```

- OpenGL ES 3.0, not raylib's default ES 2.0: the game's shaders hash with `uint` arithmetic, which GLSL ES 1.00 lacks and GLSL ES 3.00 has. The cmake warning "You are overriding the suggested GRAPHICS=GRAPHICS_API_OPENGL_ES2 with GRAPHICS_API_OPENGL_ES3!" is expected.
- Precision patch (0126): `precision mediump float;` becomes `precision highp float;` in the two OpenGL ES3 default shaders of `rlgl.h` (`rlLoadShaderDefault`). mediump is 16 bit on Mali, so without it everything raylib's batch and default shader draw (the held block, models, particles) jitters by a fraction of a block as the camera moves. The game's own shaders get highp from `shader_source_for_gles`.
- Key queue patch (0133): the key branch of `AndroidInputCallback` in `platforms/rcore_android.c` appends every key down to the 16 entry `keyPressedQueue` without checking its count, and the IME committing a long word delivers every character's key down in one poll. The append is bounded as in `rcore_desktop_glfw.c`, so keys past the sixteenth in a frame are dropped.
- Each patch script fails unless it rewrites exactly the expected lines (two, then one), so a raylib upgrade that moves the text is noticed.
- The archive holds `rcore_android.c` (`android_main`, `GetAndroidApp`) and its own copy of `android_native_app_glue.c` (`ANativeActivity_onCreate`), no GLFW. The binding links it with `system:log`, `system:android`, `system:EGL`, `system:GLESv3` and `system:OpenSLES`.

## Entry point

Facts checked in Odin dev-2026-09 (nightly a2fb372):

- `odin build -target:linux_arm64 -subtarget:android` refuses the executable build mode ("Unsupported -build-mode for -subtarget:android"). In shared mode the runtime exports a C `main` that returns 0 at once (`base/runtime/entry_unix.odin`), and the library has no INIT entry (`llvm-readelf -d`) although the link passes `-Wl,-init`, so the runtime never starts on its own.
- raylib's `android_main` calls `main(1, {"raylib", NULL})` on the native activity's thread. The program builds with `-build-mode:shared -no-entry-point` and `-Wl,--wrap=main`, so that call lands in `__wrap_main`, which `src/main_android.odin` exports (`@(export, link_name = "__wrap_main")`; the link name `main` is reserved in Odin).
- `__wrap_main` sets `runtime.args__`, then `context = runtime.default_context()`, calls `runtime._startup_runtime()` the first time only, then the game's `main`.
- Odin compiles the NDK's `android_native_app_glue.c` into its own archive and adds `-u ANativeActivity_onCreate`, so the symbol is exported without a flag of ours; either copy of the glue satisfies it.
- raylib's `argv` lives on `android_main`'s stack and feeds `os.args` only. The build links bionic, so `os.get_env` is bionic's `getenv` and reads the environment Android gives the app, which has no XDG variable.

### One process, many launches

Rule: the runtime starts once per process and is never cleaned up (0116).

- After Back or Home the activity ends but Android keeps the process; the next launch runs `android_main` again on a new thread in the same process. A second `_startup_runtime` would run every `@(init)` again, where `core:image`'s PNG registration asserts (a `SIGTRAP` on every other launch).
- A second `main` runs without the global initialisers, so `main` assigns or resets every mutable global before reading it: `global_string_table`, the log and console state (`logging.odin`, `logging_posix.odin`), the touch position and the pending Shift of `input_raylib.odin` (cleared by `start_input_backend`). `apply_ui_theme` (from `run_game` in `loop.odin`) assigns the `UI_*` colours of `ui_widgets.odin` before any drawing. The previous run's allocations stay.
- `_cleanup_runtime` is never called: Android ends the process without notice, and the `@(fini)` procedures only free memory and restore a terminal the app does not have.
- Quit returns from `main` while the activity lives, and raylib resets its own state for the next launch only when the activity is being destroyed (`ClosePlatform` checks `destroyRequested`). So after `main` returns, `__wrap_main` ends the process with `os.exit(0)` when `destroyRequested` is 0; a system destroyed activity returns normally and keeps the process.
- `src/platform/platform_android.odin` declares what the binding lacks: `GetAndroidApp` with the leading fields of `android_app` (up to `destroyRequested`) and `ANativeActivity`, checked against the NDK 27.3.13750724 headers, plus `__android_log_write` and `glGetString`.

## Link

Gotcha: a shared library links with undefined symbols without complaint, and the phone then refuses it at `dlopen` ("cannot locate symbol __real_fopen referenced by libmain.so"). `-Wl,--no-undefined` turns that into a link error here.

- `-Wl,--wrap=fopen`: raylib reads files through `__wrap_fopen`, which serves a read from the APK's assets first and calls `__real_fopen` otherwise. The wrap must be applied at the link that makes the final library; a static archive cannot carry it. With it, `llvm-nm -D --undefined-only libmain.so` lists `fopen` as an ordinary libc import.
- `-Wl,--wrap=<name>` for six glibc functions Odin's core links on Linux that Android 9's bionic lacks. `src/android_libc/` exports each as `__wrap_<name>`:

| Function | Why missing | Stand in |
|---|---|---|
| `__errno_location` (`core:c/libc`) | bionic calls it `__errno` | Calls `__errno` |
| `pthread_setcancelstate`, `pthread_setcanceltype` (`core:thread` on every thread) | bionic has no thread cancellation | Succeed, do nothing |
| `backtrace`, `backtrace_symbols`, `backtrace_symbols_fd` (`core:debug/trace`, the crash handler) | bionic has them from API 33 | Return no frames |

- An export under the plain name does not work: the same name is declared as a foreign procedure elsewhere in the program (`core:c/libc`, `logging_posix.odin`) and the compiler emits only one of the two, not always the same one.
- `core:thread` and `core:sys/posix` link `system:pthread`, which the NDK lacks (bionic keeps pthread in libc), so an empty archive `build/android/linker-shims/libpthread.a` stands in.
- The one undefined symbol left is `memfd_create`, a weak reference from the NDK's compiler runtime, which the loader allows.
- The crash signal handlers are not installed on Android: bionic's `sigaction` struct puts `sa_flags` first while `core:sys/posix` follows glibc with the handler first, so the call installed SIG_DFL with stray flags. Android's crash reporter writes the native trace to logcat (`adb logcat -s DEBUG`).

## Building the APK

`./build.sh check-android` runs `odin check src -target:linux_arm64 -subtarget:android -vet -strict-style` with `tools/android_env.sh` sourced. It runs on the host (`odin check` needs the NDK, not Java) and takes neither `-minimum-os-version` (`odin check` refuses it) nor the shared build mode.

`./build.sh android`, without `java` on the `PATH`, re-runs itself in the container (`distrobox enter mine-oh-belowed-android -- ./build.sh android`); the output lands in the same tree. Then:

1. `odin build src -target:linux_arm64 -subtarget:android -minimum-os-version:28 -build-mode:shared -no-entry-point -o:speed -vet -strict-style` with the link flags above and the `BUILD_INFO` define, into `build/android/bundle/lib/lib/arm64-v8a/libmain.so`.
2. `data/` copied to `build/android/bundle/assets/data/`, its file list (`find data -type f | sort`) to `assets/data_files.txt`, `tools/android/res/` to `res/`.
3. `tools/android/AndroidManifest.xml` rendered with `@VERSION_CODE@` (the commit count, `git rev-list --count HEAD`, so each newer build installs over the last) and `@VERSION_NAME@` (the build info).
4. `odin bundle android bundle` with the committed keystore, in `build/android/`; `test.apk` renamed to `mine-oh-belowed.apk`. The script prints the path, size, version code and build info.

- `odin bundle android <dir>` runs `aapt package` on `<dir>/AndroidManifest.xml` (with `<dir>/res` and `<dir>/assets`), then `zipalign` and `apksigner` from the smallest `build-tools/<n>` at or above the API level, against `platforms/android-<n>/android.jar`, and writes `test.apk` in the working directory.
- Gotcha: it hands aapt `<dir>/lib` as a directory, and aapt adds its contents at the APK root, so the library sits at `<dir>/lib/lib/arm64-v8a/libmain.so` to land at `lib/arm64-v8a/libmain.so`.
- An `android:label` given as a literal string does not show in `aapt dump badging`; the `@string` resource from `res/values/strings.xml` does.
- `tools/android/debug.keystore` (alias `androiddebugkey`, passwords `android`, RSA 2048, 10000 days, `CN=Android Debug, O=Android, C=US`, made with `keytool -genkeypair`) is committed on purpose: Android installs an update only over an app with the same signature, so the couch and CI must sign alike, and a debug key guards nothing.
- The manifest (`io.github.tubbles.mineohbelowed`, `NativeActivity` with `lib_name` main, landscape, GL ES 3.0 required) asks for `android.permission.VIBRATE` (a normal permission granted at install) and `android.permission.MANAGE_EXTERNAL_STORAGE` (Export below).
- Checking an APK: `llvm-nm -D libmain.so` shows `__wrap_main`, `android_main` and `ANativeActivity_onCreate`; `aapt dump badging <apk>` names the package, SDK levels, `uses-gl-es: '0x30000'` and `native-code: 'arm64-v8a'`; `apksigner verify --print-certs <apk>` passes (v3 scheme).

## Files on the phone

- Android starts the game with no environment, so `platform_directories` takes the activity's paths (`android_platform_directories`, `platform_paths.odin`): the external files folder `Android/data/io.github.tubbles.mineohbelowed/files/`, which USB and file managers with access reach, else the internal one.

| Path under the files folder | Holds |
|---|---|
| `state/mine-oh-belowed/` | `log.txt`, `screenshots/`, `texture_edits.sjson`, `data_edits/` (the data edits overlay, whose copies win over the app's data) |
| `share/mine-oh-belowed/saves/` | Saves |
| `config/mine-oh-belowed/` | `config.sjson`, `config.d/`, the saved touch layouts (`touch_overlay.sjson`) |

- Every log line also goes to logcat with the tag `mine-oh-belowed` at priority info.
- Data: `core:os` reads the real file system only and the asset manager cannot list a directory, so at start `resolve_data_directory` copies every file in `assets/data_files.txt` from the APK (read through `rl.LoadFileData`, which raylib's fopen wrapper serves from the assets) to the internal folder `/data/user/0/io.github.tubbles.mineohbelowed/files/data/`, then writes the build info to `data/.build_stamp`. A start whose stamp matches skips the copy; any other start removes the old copy first, so a file a newer build dropped does not linger. A failure logs `error: cannot copy <file> from the app: ...` and the start ends as with a missing data directory.
- Directories: every directory goes through `make_directory_path` (`platform_paths.odin`, 0117), a `mkdir -p` that tries the directory, makes a missing parent the same way and tries again, never touching a directory above the first missing one. `os.make_directory_all` opens `/` to walk an absolute path, which the SELinux policy refuses an app (`Permission_Denied` for the saves, the settings, the log and the command socket). `test_game_sources_do_not_call_make_directory_all` fails on any `os.make_directory_all` in a non test source.

## Display and shaders

- raylib opens the window at the screen's size (`InitWindow(0, 0, ...)`); the window mode and resolution settings do nothing, vsync and the frame rate cap apply. The window platform reads `android`.
- The shaders pass through `shader_source_for_gles` ([presentation.md](presentation.md), Shaders).

## Haptics

The raylib backend plays the frame's `Haptic_Request` on the phone's vibrator (`src/haptics_android.odin`, 0122; `haptics_desktop.odin` holds the no-op elsewhere). The behaviour is in [input.md](input.md), Android.

- `start_vibrator` calls `activity.getSystemService("vibrator")`, keeps the service and `android.os.VibrationEffect` as global references with the method ids of `vibrate(VibrationEffect)`, `cancel` and the static `createOneShot(long, int)`, calls `hasVibrator` and `hasAmplitudeControl` once, and logs `haptics: vibrator found, amplitude control yes` (or what failed).
- A frame's one shot is `createOneShot(HAPTIC_RUMBLE_MILLISECONDS, amplitude)` with `vibration_amplitude` (`haptics.odin`), or `VIBRATION_DEFAULT_AMPLITUDE` (-1) without amplitude control; the stop is `cancel()`.
- JNI: a `JNIEnv` and a `JavaVM` point to a pointer to a table of function pointers; the helpers of `src/platform/jni_android.odin` (`Jni_Calls`, shared with the export's access check) read a slot through `jni_function` by the indices in `src/platform/jni_indices.odin`, counted from the members of `struct JNINativeInterface` and `struct JNIInvokeInterface` in the NDK's `jni.h` and checked by `jni_indices_test.odin`.
- Calls use the `Call...MethodA` variants (arguments as a `jvalue` array), so no call from Odin goes through C varargs. Every call checks `ExceptionCheck` and a nil result; a thrown exception is cleared, and either failure is logged once and turns the vibrator off for the run.
- The game thread attaches to the VM before every use, since raylib's `GetCurrentMonitor` (read by `current_monitor_size`) detaches the thread when it returns; attaching an attached thread only returns its `JNIEnv`. `stop_vibrator` at the end of `run_game` cancels, frees the references and detaches, since the thread may end with the activity while the process lives.

## Keyboard

The IME opens and closes through `src/system_keyboard_android.odin` (0133; flags 0 both: an explicit request, and a hide however it was shown), declared against `system:android`; the entry's rules are in [ui.md](ui.md), On-screen keyboard. This is how its keys become text.

- raylib's Android backend queues key codes only, so `GetCharPressed` returns nothing on the phone. `read_raylib_typed_text` (`input_raylib.odin`) drains `GetKeyPressed` and turns keys into text with `character_for_key`: letters, digits, space and the punctuation raylib's `mapKeycode` table maps (minus, equals, brackets, backslash, semicolon, apostrophe, grave, comma, period, slash). Shift gives the upper case letter or the US layout's shifted character (`!` on 1, `_` on minus, `|` on backslash, `~` on grave); every other key types nothing.
- The IME types an upper case letter as Shift pressed, the letter pressed and both released, so a Shift in the queue applies to the next character only, also when it arrives in a later frame; a frame without any key after the Shift drops it.
- On every platform the queued keys join the frame's keys down (`add_pressed_keys`), since a key that goes down and up within one poll (the IME's, a virtual keyboard's on the desktop) never reads as down otherwise. `AKEYCODE_DEL` maps to `KEY_BACKSPACE` and `AKEYCODE_ENTER` to `KEY_ENTER`, so the field's Enter works; each queued Backspace becomes `TEXT_BACKSPACE` in its place in the typed text, so every Backspace in a frame deletes one character, and `advance_keyboard` then ignores the Backspace key's edge.
- raylib's queue holds 16 keys a frame (`RAYLIB_KEY_QUEUE_CAPACITY`, raylib's `MAX_KEY_PRESSED_QUEUE`); with the patched archive the keys past the sixteenth are dropped.

## Export and storage access

The Data files screen's Export and its refusals are in [developer_tools.md](developer_tools.md), Export; this is what the phone's storage needs (0131).

- Syncthing cannot reach the app's files folder under scoped storage, so the export goes to shared storage, for example `/storage/emulated/0/Syncthing/mine` (the folder's path as the phone's Syncthing app shows it). The phone has no home directory for a `~/` path.
- Writing there needs All files access: `MANAGE_EXTERNAL_STORAGE`, granted only on Android's settings page, and restricted on Google Play, which does not matter for this sideloaded build.
- Before an export, and before an export on save, the game asks `Environment.isExternalStorageManager()` through JNI (`src/platform/export_access_android.odin`; `export_access_desktop.odin` answers yes elsewhere). On no it opens the app's page of that setting (`startActivity` of an `Intent("android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION")` with `Uri.fromParts("package", <package>, null)`) and toasts "Allow All files access, then export again": turn it on, return, press Export again.
- A device without the per app page (`startActivity` throws `ActivityNotFoundException`, cleared and logged) gets the list of every app's access (`android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION`, no URI).
- Before Android 11 (API 30) the method does not exist: the failed lookup is logged and the export goes ahead, so a refused write toasts with its path. Those versions would need `WRITE_EXTERNAL_STORAGE`, which the manifest does not ask for.
- The JNI slots added for it are `NewObjectA` (30) and `CallStaticBooleanMethodA` (119).
- With Export on save, the couch sees an edit a few seconds after the Save; the export's stall is in [developer_tools.md](developer_tools.md).

## CI and installing

- The CI job `android` on `ubuntu-latest` checks out with `fetch-depth: 0` (the commit count), downloads `odin-linux-amd64-dev-2026-09.tar.gz` (SHA-256 checked), prints the runner's Android tools and Java, and runs `MINE_OH_BELOWED_COMMIT=<short commit> ./build.sh check-android` and `./build.sh android` with the runner's `ANDROID_HOME`. The APK is uploaded as `mine-oh-belowed-android-arm64-<short commit>`.
- Download it from the workflow run (Actions, the run, Artifacts) or `gh run download <run id> --name mine-oh-belowed-android-arm64-<short commit>`; it arrives as a zip holding `mine-oh-belowed.apk`. Copy it to the phone, open it, allow installs from that source, install. Couch and CI builds install over each other, since both sign with the committed key and the version code only grows.
- With USB debugging on, `adb install -r build/android/mine-oh-belowed.apk` and `adb logcat -s mine-oh-belowed raylib` work from the container (`platform-tools` is on the `PATH` after sourcing `tools/android_env.sh`).

## What the Android build lacks

- SDL3 and with it the Steam Controller features (trackpads, gyro, grip sense); the magnetometer's haptics play on the vibrator instead.
- A command socket client: `tools/moc` runs on Linux, while the game still opens its socket under the state folder in developer mode where the file system allows one.
- The couch launcher, the play build installer and crash back traces.
- The local time zone: `timezone.region_load("local")` finds no database, so the title screen's dates are UTC.
- A launcher icon.
