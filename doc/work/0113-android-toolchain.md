# 0113 Android toolchain: raylib for Android, the SDK tools and a hello world APK

Status: implemented
Milestone: M11

## Goal

The native Android app (spitball with the user, 2026-09-29: the game as an APK with its own touch overlay instead of Winlator) needs three things this machine lacks: a raylib built for Android arm64 with OpenGL ES 3.0, Odin's Android link (the NDK's clang, `ODIN_ANDROID_NDK`) and `odin bundle android` (`ODIN_ANDROID_SDK` with `build-tools`, `platforms` and a Java for `apksigner`). The couch (Bazzite, immutable, no Java) gets them through a distrobox and `~/opt/android/sdk`, the CI runner (ubuntu-24.04) already ships them at `ANDROID_HOME=/usr/local/lib/android/sdk` with NDK 27.3.13750724, build-tools 34.0.0, platforms android-34 and JDK 17. This item ends with a hello world APK that starts on the phone; the game itself is the next item.

Facts checked in the Odin dev-2026-09 sources (`tmp/odin-src/build_settings.cpp`, `linker.cpp`, `bundle_command.cpp`):

- `odin build -target:linux_arm64 -subtarget:android` reads `ODIN_ANDROID_SDK`, `ODIN_ANDROID_NDK` (the toolchain defaults to `<ndk>/toolchains/llvm/prebuilt/linux-x86_64`) and `-minimum-os-version:<api level>` (default 34). `odin check` for that target also needs `ODIN_ANDROID_NDK` set.
- Entry point, verified 2026-09-29 (replaces the plan's executable mode fact): `odin build -target:linux_arm64 -subtarget:android` refuses the executable build mode, "Unsupported -build-mode for -subtarget:android", "Currently only supporting: shared, object, assembly, llvm-ir" (`build_settings.cpp`, the `Subtarget_Android` switch). In `-build-mode:shared` the runtime's exported C `main` (`base/runtime/entry_unix.odin`, `ODIN_BUILD_MODE == .Dynamic`) is `mov w0, wzr; ret`, and the output has no INIT entry in `llvm-readelf -d` although the link line passes `-Wl,-init,'_odin_entry_point'`, so neither the runtime startup nor `main::main` would run. The link name `main` is reserved in Odin. What works: `-build-mode:shared -no-entry-point -extra-linker-flags:-Wl,--wrap=main` and an exported `@(export, link_name = "__wrap_main") proc "c" (argc: i32, argv: [^]cstring) -> i32` that sets `runtime.args__ = argv[:argc]`, `context = runtime.default_context()`, calls `runtime._startup_runtime()`, the program, `runtime._cleanup_runtime()` and returns 0. `llvm-objdump -d` shows raylib's `android_main` calling `bl __wrap_main@plt`. raylib passes `argv = {"raylib", NULL}` from `android_main`'s stack, so `core:os`, which finds the environment behind `args__` (`env_linux.odin`, `_get_original_env` starts at `argv[argc]`, that NULL), sees an empty environment on Android: every variable reads as unset, nothing reads past the array.
- Odin compiles `<ndk>/sources/android/native_app_glue/android_native_app_glue.c` itself with the NDK toolchain, links it as a static archive ahead of the objects and passes `-u ANativeActivity_onCreate` itself (seen with `-show-system-calls`), so no `-u` flag of ours is needed. raylib's archive holds its own copy of the glue; the link takes one without complaint and `nm -D` shows `ANativeActivity_onCreate`.
- `odin bundle android <dir>` packages `<dir>/AndroidManifest.xml`, `<dir>/lib/` (`lib/arm64-v8a/libmain.so`) and optional `<dir>/assets/` and `<dir>/res/` with `aapt`, `zipalign` and `apksigner` from `<sdk>/build-tools/<n>/`, picking the smallest `<n>` at or above the API level and `<sdk>/platforms/android-<n>/android.jar` (so build-tools 34.0.0 needs platforms android-34); flags `-android-keystore`, `-android-keystore-alias`, `-android-keystore-password`, `-minimum-os-version`. It names the output `test.apk` in the working directory (confirmed); rename it. Quirk, verified: it hands aapt `<dir>/lib` as a directory argument and aapt adds that directory's contents at the APK root, so `<dir>/lib/arm64-v8a/libmain.so` lands at `arm64-v8a/libmain.so`, where Android does not look. The library goes to `<dir>/lib/lib/arm64-v8a/libmain.so` instead, which lands at `lib/arm64-v8a/libmain.so`.
- raylib 6.0's cmake (`tmp/raylib-src/cmake/LibraryConfigurations.cmake`) with `-DPLATFORM=Android` compiles `rcore_android.c` with the NDK's glue, forces `GRAPHICS_API_OPENGL_ES2`, and `-DOPENGL_VERSION="ES 3.0"` overrides that to `GRAPHICS_API_OPENGL_ES3` with a cmake warning ("You are overriding the suggested GRAPHICS"), which is expected. Its libraries are `log android EGL GLESv2 OpenSLES atomic c m`; with ES3 the link takes `GLESv3`.

## Change

- `tools/android_toolchain.sh`: installs the SDK under `${ODIN_ANDROID_SDK:-$HOME/opt/android/sdk}`: the command line tools zip `https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip` (its SHA-256 from https://developer.android.com/studio#command-line-tools-only, checked before unpacking, recorded in the script) unpacked to `cmdline-tools/latest/`, the licenses accepted (`yes | sdkmanager --sdk_root=<sdk> --licenses`), then `sdkmanager --sdk_root=<sdk> "platform-tools" "build-tools;34.0.0" "platforms;android-34" "ndk;27.3.13750724"`, the versions the CI runner has. Re-running skips what is installed. `sdkmanager`, `apksigner` and `keytool` need Java, and Bazzite has none, so like `tools/build_raylib.sh` the script runs itself inside a distrobox, `mine-oh-belowed-android` (image `registry.fedoraproject.org/fedora-toolbox:44`, created on first use with a headless OpenJDK 17 or newer, `java-21-openjdk-headless` is expected in Fedora 44 so check with `dnf search`, plus `cmake gcc gcc-c++ make git unzip`), and `--host` runs the steps on a machine that has the tools. The home directory is shared with the container, so the SDK lands under `~/opt` either way.
- `tools/android_env.sh`: sourced by the build scripts (and by the user's shell): `ANDROID_NDK_VERSION=27.3.13750724`, `ANDROID_API_LEVEL=28` (the `-minimum-os-version`, Android 9; raylib's archive is built for the same level), `ODIN_ANDROID_SDK="${ODIN_ANDROID_SDK:-${ANDROID_HOME:-$HOME/opt/android/sdk}}"`, `ODIN_ANDROID_NDK="${ODIN_ANDROID_NDK:-$ODIN_ANDROID_SDK/ndk/$ANDROID_NDK_VERSION}"`, exported, and `build-tools/34.0.0` and `platform-tools` on the PATH. The CI runner's `ANDROID_HOME` has the same NDK version under `ndk/`, so the same file serves there.
- `tools/build_raylib.sh --android` (and `--android --host`): the same shallow clone of tag 6.0, configured in `tmp/raylib-build-android/` with `-G "Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=$ODIN_ANDROID_NDK/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28 -DPLATFORM=Android -DOPENGL_VERSION="ES 3.0" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF`, built, copied to `shared/raylib/android/libraylib.a`, and a second record block `<!-- android build record -->` appended to `shared/raylib/README.md` (the desktop record's sed must leave it alone and vice versa; the simplest is one marker per platform and each rewrite deleting from its own marker to the next marker or the end). The Android build runs in the `mine-oh-belowed-android` container (it has cmake and the NDK). Check with `nm` that the archive has `android_main` and `GetAndroidApp` and no `glfw` symbol.
- The binding: `shared/raylib/raylib.odin` and `shared/raylib/rlgl/rlgl.odin` get an Android branch ahead of the Linux one, `when ODIN_OS == .Linux && ODIN_PLATFORM_SUBTARGET == .Android`, importing `android/libraylib.a` (`../android/libraylib.a` in rlgl) with `system:log`, `system:android`, `system:EGL`, `system:GLESv3`, `system:OpenSLES`; the existing Linux lines stay byte for byte, since the nix flake's `substituteInPlace --replace-fail` patterns in `flake.nix` match them. `platform.odin` imports `android/libraylib.a` on Android too, but declares its GLFW procedures only when the subtarget is not Android (there is no GLFW in that archive), so a call from the game fails at compile time, not at link time; the next item guards the callers. `shared/raylib/README.md` records that the two binding files now carry this one patch (they were copied unchanged before) and the Android archive beside the Linux and Windows ones.
- `tools/android/debug.keystore`, committed: `keytool -genkeypair -keystore tools/android/debug.keystore -alias androiddebugkey -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug, O=Android, C=US"` (the conventions of Android's own debug key), made in the container. It is committed on purpose: Android installs an update over an installed app only when the new APK carries the same signature, so the couch and CI must sign alike, and a debug key guards nothing. Say so in `doc/build.md`.
- Proof, not committed: `tmp/android-hello/main.odin` (package `main`, `import rl "shared:raylib"`, a `main :: proc()` that calls `rl.InitWindow(0, 0, "Mine oh Belowed hello")`, loops until `rl.WindowShouldClose()` drawing a dark background, `rl.DrawText("hello from Odin", 40, 40, 40, rl.RAYWHITE)` and `rl.DrawFPS`, then `rl.CloseWindow()`) and `tmp/android-hello/bundle/AndroidManifest.xml` (package `io.github.tubbles.mineohbelowed.hello`, `uses-sdk` min 28 target 34, `uses-feature android:glEsVersion="0x00030000"`, an `application` with `android:hasCode="false"` holding one `android.app.NativeActivity` with `android:exported="true"`, `android:screenOrientation="landscape"`, `android:configChanges="orientation|keyboardHidden|screenSize"`, the `meta-data` `android.app.lib_name` = `main` and the MAIN/LAUNCHER intent filter). Build: `. tools/android_env.sh`, then `~/opt/odin/odin build tmp/android-hello -target:linux_arm64 -subtarget:android -minimum-os-version:28 -collection:shared=shared -out:tmp/android-hello/bundle/lib/arm64-v8a/libmain.so` (if Odin renames the output, note it and move the file), `nm -D` on it shows `main`, `android_main` and `ANativeActivity_onCreate` (else the `-u` flag above), then `odin bundle android tmp/android-hello/bundle -android-keystore:tools/android/debug.keystore -android-keystore-alias:androiddebugkey -android-keystore-password:android -minimum-os-version:28` run from `tmp/android-hello/`, the APK renamed to `tmp/android-hello/hello.apk`, `aapt dump badging` naming the package and `apksigner verify --print-certs` passing. Both Odin steps run inside the container as well (Odin at `~/opt/odin` works there, the home is shared; `apksigner` needs its Java). Put the manifest and the exact commands into the item's Implemented section, since the game item copies them.
- Documentation in the same commit: a `## Android toolchain` section in `doc/build.md` after the Windows one (what is installed where, the container, the env file, the raylib flags and why ES 3.0, the entry point facts above, the glue, the keystore and why it is committed, the hello world and how the APK is checked, the CI runner's matching versions); `shared/raylib/README.md` as above; `CLAUDE.md` Stack (raylib line: the Android archive `shared/raylib/android/libraylib.a`, ES 3.0, built by `tools/build_raylib.sh --android`); a dated entry in `doc/log/2026-09-29.md` (tags `#android #build #decision`).

## Verify

- `./build.sh check`, `./build.sh check-windows`, `./build.sh test`, `./build.sh release` unchanged (the binding patch must not disturb the desktop builds).
- With `tools/android_env.sh` sourced: `~/opt/odin/odin check shared/raylib -no-entry-point -vet -strict-style -target:linux_arm64 -subtarget:android` and the same for `shared/raylib/rlgl`.
- The hello world APK built, `aapt dump badging` and `apksigner verify` passing, its size and the archive's size in the Implemented section.
- User: install `tmp/android-hello/hello.apk` on the phone (copy it over and open it, or `adb install` from the container once USB debugging is on); it shows the text and a frame counter in landscape.

## Implemented

2026-09-29: `tools/android_env.sh`, `tools/android_toolchain.sh`, `tools/build_raylib.sh --android`, `shared/raylib/android/libraylib.a`, the Android branch in `shared/raylib/raylib.odin` and `rlgl/rlgl.odin`, `platform.odin` with its GLFW declarations only off Android, and `tools/android/debug.keystore` are in; `doc/build.md` (Android toolchain), `shared/raylib/README.md`, `CLAUDE.md` and `doc/log/2026-09-29.md` describe them.

Deviations from the plan, accepted: the developer page lists the command line tools `commandlinetools-linux-15859902_latest.zip` (SHA-256 `4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583`) and no longer gives a checksum for 13114758; Fedora 44 has no `java-21-openjdk-headless` (a `dnf repoquery` found `java-25-openjdk-headless` and the early access `java-latest-openjdk-headless`), so the container carries JDK 25; `tools/android_env.sh` also exports `ANDROID_BUILD_TOOLS_VERSION=34.0.0` and `ANDROID_PLATFORM_VERSION=34` so the versions live in one file. The entry point is `--wrap=main` in shared mode, not the executable mode (facts above). `platform.odin` marks `import "core:c"` and the Android `foreign import` with `@(require)`: on Android nothing in the file uses them, and `-vet` refused the unused imports. `tools/build_raylib.sh --android` strips the archive's debug sections (`llvm-strip --strip-debug`): 12261862 bytes before, 2550222 after; `llvm-nm` still shows `android_main`, `GetAndroidApp` and `ANativeActivity_onCreate`, and no `glfw` symbol. The build records now end at the next record marker instead of the end of the file, so the desktop and Android records rewrite independently.

Commands, from the repository root (the SDK steps and both Odin steps inside `distrobox enter mine-oh-belowed-android`, where the NDK, Java and `~/opt/odin` all work):

```
tools/android_toolchain.sh
tools/build_raylib.sh --android
distrobox enter mine-oh-belowed-android -- keytool -genkeypair -keystore tools/android/debug.keystore -alias androiddebugkey -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug, O=Android, C=US"

# inside the container:
. tools/android_env.sh
mkdir -p tmp/android-hello/bundle/lib/lib/arm64-v8a
~/opt/odin/odin build tmp/android-hello -build-mode:shared -no-entry-point -target:linux_arm64 -subtarget:android -minimum-os-version:"$ANDROID_API_LEVEL" -collection:shared=shared -extra-linker-flags:-Wl,--wrap=main -out:tmp/android-hello/bundle/lib/lib/arm64-v8a/libmain.so
cd tmp/android-hello
~/opt/odin/odin bundle android bundle -android-keystore:../../tools/android/debug.keystore -android-keystore-alias:androiddebugkey -android-keystore-password:android -minimum-os-version:"$ANDROID_API_LEVEL"
mv test.apk hello.apk
aapt dump badging hello.apk
apksigner verify --verbose --print-certs hello.apk
```

`tmp/android-hello/main.odin`:

```
package main

import "base:runtime"
import rl "shared:raylib"

@(export, link_name = "__wrap_main")
wrapped_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
	runtime.args__ = argv[:argc]
	context = runtime.default_context()
	runtime._startup_runtime()
	hello()
	runtime._cleanup_runtime()
	return 0
}

hello :: proc() {
	rl.InitWindow(0, 0, "Mine oh Belowed hello")
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground({20, 20, 28, 255})
		rl.DrawText("hello from Odin", 40, 40, 40, rl.RAYWHITE)
		rl.DrawFPS(40, 100)
		rl.EndDrawing()
	}
	rl.CloseWindow()
}
```

`runtime.args__` is public in `base/runtime/core.odin`, so the assignment compiles from outside the runtime.

`tmp/android-hello/bundle/AndroidManifest.xml`:

```
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
	package="io.github.tubbles.mineohbelowed.hello"
	android:versionCode="1"
	android:versionName="0.1">
	<uses-sdk android:minSdkVersion="28" android:targetSdkVersion="34" />
	<uses-feature android:glEsVersion="0x00030000" android:required="true" />
	<application android:label="@string/app_name" android:hasCode="false">
		<activity
			android:name="android.app.NativeActivity"
			android:exported="true"
			android:screenOrientation="landscape"
			android:configChanges="orientation|keyboardHidden|screenSize">
			<meta-data android:name="android.app.lib_name" android:value="main" />
			<intent-filter>
				<action android:name="android.intent.action.MAIN" />
				<category android:name="android.intent.category.LAUNCHER" />
			</intent-filter>
		</activity>
	</application>
</manifest>
```

with `tmp/android-hello/bundle/res/values/strings.xml` holding `<string name="app_name">Mine oh Belowed hello</string>`: with a literal `android:label` the badging printed `application: label=''` and no `application-label:` line; with the string resource it prints `application-label:'Mine oh Belowed hello'`.

Verified here: `./build.sh check`, `./build.sh check-windows`, `./build.sh test` (1061 tests) and `./build.sh release` pass; with the env sourced, `odin check shared/raylib -no-entry-point -vet -strict-style -target:linux_arm64 -subtarget:android` and the same for `shared/raylib/rlgl` pass. `libmain.so` is 799128 bytes and exports `__wrap_main`, `android_main`, `ANativeActivity_onCreate` and the runtime's stub `main`; `android_main` calls `bl __wrap_main@plt`. `tmp/android-hello/hello.apk` is 360864 bytes and holds `AndroidManifest.xml`, `lib/arm64-v8a/libmain.so` and `resources.arsc`. `aapt dump badging` prints package `io.github.tubbles.mineohbelowed.hello`, `sdkVersion:'28'`, `targetSdkVersion:'34'`, `application-label:'Mine oh Belowed hello'`, `launchable-activity: name='android.app.NativeActivity'`, `uses-gl-es: '0x30000'` and `native-code: 'arm64-v8a'`. `apksigner verify --print-certs` prints "Verifies" with the v3 scheme, signer `CN=Android Debug, O=Android, C=US`, certificate SHA-256 `346bd9f18ac7b8f3138a2b53601a4fda06584b6296236778f1c9ef3d254b9b59`; under JDK 25 it also prints four "restricted method" warnings about conscrypt's `loadLibrary`, harmless. Not verified: the APK on a phone (the user's check below).

Candidate upstream reports for Odin: `odin bundle android` adds `<dir>/lib`'s contents at the APK root (the `lib/lib/` layout works around it); the shared library has no INIT entry although the link passes `-Wl,-init,'_odin_entry_point'` (read from `-show-system-calls`; the quotes may reach the linker literally, not checked).

2026-09-29, phone test: the hello APK failed at `dlopen` with "cannot locate symbol __real_fopen referenced by libmain.so"; the link needs `-Wl,--wrap=fopen` (raylib's `rcore_android.c` wraps `fopen`, and a static archive cannot apply the wrap itself), added in 0114 together with `-Wl,--no-undefined`.
