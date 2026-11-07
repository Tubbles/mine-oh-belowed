# 0315: Float the toolchains and turn CI green

Status: landed (2026-11-07, a994f07)

The user (2026-11-07): "Let's only pin when there's a good reason. Have packages float on latest as a general rule, and we'll integrate them as necessary as it shows up." CI's `nix` job has failed on every push since 2026-11-05: `flake.nix` follows `nixos-unstable`, whose Odin moved from dev-2026-09 to dev-2026-10, and the new Odin refuses the flake's `odin check src -target:windows_amd64` on Linux without `-windows-sdk-root`. The build and all tests pass there on dev-2026-10.

## Goal

CI is green on the latest toolchains, and every pin left in the repository carries its reason beside it.

## Controls

None.

## Change

- The pins found on 2026-11-07:
  - Odin dev-2026-09: the local `~/opt/odin` (`CLAUDE.md`, `doc/build.md`), and the CI `windows` and `android` jobs (release URL and SHA-256).
  - SDL3 3.4.16: the CI `windows` job.
  - The Android tools: NDK 27.3.13750724, build-tools 34.0.0 and platform 34 in `tools/android_env.sh`, which CI uses too, and the command line tools zip with its SHA-256 in `tools/android_toolchain.sh`.
  - raylib 6.0: the tag `tools/build_raylib.sh` builds the committed archives in `shared/raylib` from, with patches.
  - Not pins: nixpkgs follows `nixos-unstable` with no lock, and the GitHub actions float within their major tags.
- The `nix` job passes on dev-2026-10. Either the Windows cross check gets what the new Odin asks for, or it leaves the flake because the `windows` job builds natively on every push. The local `./build.sh check-windows` follows the same choice.
- The `windows` and `android` jobs take the latest Odin and SDL3 releases. The Android NDK and build-tools take the newest the runner holds.
- What stays pinned states why beside the pin. Candidates are raylib, whose committed archives are built with patches, and the Android platform level, a product target rather than a tool.
- The local Odin moves to the latest release, dev-2026-11a (the user approved the install, 2026-11-07), and the code is ported to it; the landing switches the `~/opt/odin` link. nixpkgs' Odin may lag, and the docs say so.
- Docs: `CLAUDE.md` (Stack), `doc/build.md` (the toolchain table, CI), `doc/android.md` (the tools, CI).

## Verify

- CI green on all three jobs after the push.
- The checks and the suite locally.
- The CI APK on the phone: it starts, starts again after Back, and Quit ends it.

## Specification (design, 2026-11-07)

Scope widened by the main agent: the target is dev-2026-11a, installed at `/var/home/Tubbles/opt/odin-linux-amd64-nightly+2026-11-03` (`odin version`: dev-2026-11-nightly:9a69916). Every fact below was read in Odin's source at the tags or checked by building a scratch copy of `src/` with dev-2026-09 and dev-2026-11a. With the port below applied there, 11a checks `check`, `check-windows` and `check-android` without a warning and passes all 2202 tests; 09 checks `check` and `check-windows` and passes all 2202 tests.

### Decisions

1. Order. With the changes below, `src/` checks clean on 09 and 11a for the desktop and Windows targets, and on 11a only for Android: the Android declarations follow 11a's libc, `check-android` passes `-minimum-os-version`, which `odin check` takes from dev-2026-11 on (Odin `c894772878`), and 11a's `odin bundle android` wants another library layout. So the landing switches `~/opt/odin` to the 11a directory (main agent, before the suite on `main`). The implementer and the verifier run every command with `ODIN=/var/home/Tubbles/opt/odin-linux-amd64-nightly+2026-11-03/odin`, and `./build.sh check` and `./build.sh test` once more with the default dev-2026-09, which stands in for nixpkgs' dev-2026-10 (the same `bytes.Buffer` pixels and the same `^va_list` vsnprintf at both tags).
2. nixpkgs at dev-2026-10: feasible. The flake builds and tests only `linux_amd64`, where 10 and 11a differ for this code only in the decoded pixels (port 1); vsnprintf on amd64 is declared alike in 09, 10 and 11a.
3. The Windows cross check leaves the flake. dev-2026-10 alone cannot run it: `-windows-sdk-root` is a `build` only flag there while the refusal fires for every command on a non-Windows host. Odin `0701fb61c5` (2026-10-12, in dev-2026-11) refuses only commands that link (build, run, test of an executable or library), so `odin check -target:windows_amd64` runs on 09 and 11a without the flag. Dropped anyway: the `windows` job compiles the same target natively with `-vet -strict-style` and links it on every push. `./build.sh check-windows` stays the local check. `test_static_runtime_imports_stay_out_of_windows` does not cover what the cross check did: it reads two imports' build tags, a link concern `odin check` never saw; the compile coverage moves to the `windows` job.
4. Odin and SDL3 on CI: the latest release through the GitHub API, the download checked against the asset's `digest` (SHA-256 GitHub records at upload). The releases publish no checksum file (11a's assets are the four archives). The digest catches a broken download, not a replaced asset; a floating version cannot carry a pinned hash. Odin assets are selected by the prefix `odin-<platform>-` (dev-2026-10 dropped macos-amd64): no match or two fail the step and list the release's assets. SDL3 is the highest `release-3.x.y` that is neither draft nor prerelease, by version, not date: SDL 2's `release-2.32.x` share the repository, and an older 3.x line can publish the same day as a newer one (3.2.30 and 3.4.0, 2026-01-01).
5. Android tools: the NDK and build-tools float to the newest installed under the SDK (the runner holds NDK 27.3, 29.0 and 30.0, build-tools 34.0.0 to 37.0.0). 11a's bundler takes the newest build-tools and platform itself. Pinned, with the reason beside them: the target SDK 34 (a product target: it opts the app into that release's behaviour changes, which the phone was tested against), and the command line tools zip with its SHA-256 (it only bootstraps sdkmanager, which installs the floating packages). The minimum API level moves 28 to 29: dev-2026-11 refuses less (its runtime uses ELF thread local storage, which Android loads from 29), so Android 9 phones lose the game.
6. raylib 6.0 stays pinned: the committed Linux and Android archives and `windows/raylib.lib` are 6.0, the Android one with three patches, and `shared/raylib`'s binding is the 6.0 copy, so a raylib release is a rebuild of all three plus a phone test, its own item. raylib 6.2 (2026-10-15) contains `a005a044d`, the fix of the third patch, and 11a's `vendor:raylib` binds 6.2, so this item does not redo the binding copy.

### Port to dev-2026-11a

1. `src/render_atlas.odin`, `tile_from_image`: `decoded.pixels.buf[:]` becomes `image_pixel_bytes(&decoded.pixels)`; `import "core:bytes"`; above `tile_from_image` (Odin #8153 made `Image.pixels` a `[dynamic]u8`):
   ```odin
   // core:image keeps the decoded pixels in a bytes.Buffer up to Odin
   // dev-2026-10 and in a [dynamic]u8 from dev-2026-11, and the nix job
   // builds with nixpkgs' Odin, which may lag: the group takes either
   // (0315). The buffer half goes once nixpkgs has dev-2026-11.
   image_pixel_bytes :: proc {
   	image_pixel_bytes_of_buffer,
   	image_pixel_bytes_of_dynamic_array,
   }

   image_pixel_bytes_of_buffer :: proc(pixels: ^bytes.Buffer) -> []u8 {
   	return pixels.buf[:]
   }

   image_pixel_bytes_of_dynamic_array :: proc(pixels: ^[dynamic]u8) -> []u8 {
   	return pixels[:]
   }
   ```
2. `src/raylib_log.odin`, the non-Windows branch, no libc import. core:sys/posix imports core:c/libc on every target but Windows, Odin refuses a second foreign declaration of a link name with another signature (`check_link_name_uses`), and 11a's libc (`baca00868b`) passes the va_list by value except on amd64 System V. raylib hands the callback its va_list by value; on arm64 that 32 byte struct travels as a pointer to a copy, which the callback's `^c.va_list` holds, so `arguments^` passes vsnprintf the same list. On 09 or 10 for arm64 this declaration would clash in turn (accepted, decision 1).
   ```odin
   	// C passes a va_list by value: on x86-64 an array, which decays to a
   	// pointer, on arm64 a struct. Odin dev-2026-11's core:c/libc declares
   	// vsnprintf so, core:sys/posix brings that declaration into every
   	// build but Windows, and Odin refuses a second one of the same name
   	// with another signature (0315).
   	when ODIN_ARCH == .amd64 {
   		Va_List_Argument :: ^c.va_list
   	} else {
   		Va_List_Argument :: c.va_list
   	}

   	@(default_calling_convention = "c")
   	foreign c_runtime {
   		vsnprintf :: proc(buffer: [^]u8, size: c.size_t, format: cstring, arguments: Va_List_Argument) -> c.int ---
   	}

   	format_trace_log :: proc "c" (buffer: []u8, text: cstring, arguments: ^c.va_list) {
   		when ODIN_ARCH == .amd64 {
   			vsnprintf(raw_data(buffer), c.size_t(len(buffer)), text, arguments)
   		} else {
   			vsnprintf(raw_data(buffer), c.size_t(len(buffer)), text, arguments^)
   		}
   	}
   ```
3. The Android main. 11a refuses a `main` on Android unless a package calls `intrinsics.__entry_point` (checker.cpp, "Nothing calls 'main' on Android"); the shared build with `-no-entry-point` clears it, `odin check` cannot take `-build-mode:shared`. Importing `core:sys/android/native_app_glue` is no way out: it defines `ANativeActivity_onCreate`, which raylib's archive defines, and raylib's `android_main` drives the game. So:
   - `src/main.odin`: `main :: proc()` becomes `game_main :: proc()`, body unchanged.
   - New `src/main_desktop.odin`:
     ```odin
     #+build !linux:android
     package game

     // The entry point everywhere but Android, whose build has none: Odin
     // dev-2026-11 refuses a main there that nothing calls through
     // intrinsics.__entry_point, and main_android.odin's __wrap_main runs
     // game_main (0315).
     main :: proc() {
     	game_main()
     }
     ```
   - `src/main_android.odin`: `main()` becomes `game_main()`, and the header comment's "runs the game's main" says `game_main`.
   - `build.sh` `check_android`: `"$odin" check src "$collection" -target:linux_arm64 -subtarget:android -minimum-os-version:"$ANDROID_API_LEVEL" -no-entry-point -vet -strict-style` (without `-no-entry-point` the check asks for a main; the build passes it already; the level makes the check see what the build sees).
4. The runtime start. 11a's library has an INIT entry, `_odin_entry_point`, which sets `args__` and runs `_startup_runtime` when Android loads the library (`llvm-readelf -d`: INIT and FINI on 11a, none on 09). `__wrap_main` would start it again, every `@(init)` twice, and core:image/png's registration asserts (0116). `src/main_android.odin`, after `runtime_started`:
   ```odin
   // Every @(init) procedure runs inside _startup_runtime, so this marks
   // the start: from Odin dev-2026-11 the library's INIT entry starts the
   // runtime when Android loads it; in dev-2026-09 nothing did and
   // __wrap_main started it (0315).
   @(init, private = "file")
   note_runtime_started :: proc "contextless" () {
   	runtime_started = true
   }
   ```
   and `__wrap_main` drops the `runtime_started = true` after `runtime._startup_runtime()`. The FINI (`_odin_exit_point`) does not run on Quit: `os.exit` ends the process with `exit_group` (`base/runtime/os_specific_linux.odin`), so the runtime is still never cleaned up.
5. The activity's entry. 11a no longer compiles the NDK's glue nor adds `-u ANativeActivity_onCreate` (linker.cpp: programs using raylib "no longer get the NDK's C glue"), and nothing references raylib's copy in the archive, so the 11a library exported no `ANativeActivity_onCreate` and Android could not start it. `build.sh` `build_android`: `-Wl,-u,ANativeActivity_onCreate` joins `android_linker_flags` after `-Wl,--no-undefined` (checked: exported again), and after the `odin build`:
   ```bash
   	local exports
   	exports="$("$ODIN_ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm" -D --defined-only "$android_bundle/lib/arm64-v8a/libmain.so")"
   	if [[ "$exports" != *" T ANativeActivity_onCreate"* ]]; then
   		echo "libmain.so exports no ANativeActivity_onCreate, so Android cannot start it" >&2
   		exit 1
   	fi
   ```
   (a variable, since `| grep -q` can end llvm-nm with SIGPIPE under `pipefail`). The comment above `build_android` names the flag and why.
6. The bundle. 11a's `odin bundle android` runs aapt2 with the newest build-tools and platform under `ODIN_ANDROID_SDK` (the manifest's levels win over its defaults), copies `<dir>/lib/` into the APK's `lib/` as it is, adds Odin's `classes.dex` (unused, `android:hasCode="false"`), aligns with `zipalign -P 16 -f 4`, signs with apksigner (Java from `JAVA_HOME` or the `PATH`) and writes `-out:` (default `<dir>.apk`). `build_android`: the library goes to `bundle/lib/arm64-v8a/libmain.so` (the `mkdir -p` and `-out:` follow); `rm -f mine-oh-belowed.apk mine-oh-belowed.apk.idsig` before the bundle; `"$odin" bundle android bundle -out:"$android_directory/mine-oh-belowed.apk"` with the keystore flags and `-minimum-os-version:"$ANDROID_API_LEVEL"`; `rm -f mine-oh-belowed.apk.idsig` after (apksigner's v4 file); the `test.apk` lines go; the sed renders `@MIN_SDK_VERSION@` from `ANDROID_API_LEVEL` and `@TARGET_SDK_VERSION@` from `ANDROID_TARGET_SDK_VERSION`. `tools/android/AndroidManifest.xml`: `<uses-sdk android:minSdkVersion="@MIN_SDK_VERSION@" android:targetSdkVersion="@TARGET_SDK_VERSION@" />`, its header comment naming the two levels and `tools/android_env.sh`.
7. Warnings. 11a's escape analysis (Odin #7802) flags `platform.begin_log_capture(&capture)` five times (data_reload.odin:47, hot_reload.odin:105 and 120, main.odin:460, loop.odin:2236): the procedure stores the address of the caller's local in the thread local `captured_log_error`. Intended: each caller ends the capture before any return, and `end_log_capture` restores the previous pointer. `src/platform/logging.odin` `begin_log_capture`: `captured_log_error = (^string)(rawptr(&capture.captured))`, commented: "The caller's local stays referenced until end_log_capture puts the previous pointer back, so a capture begins and ends in one procedure with no return between. The conversion tells Odin dev-2026-11's escape analysis so (0315)." The explicit conversion is the analysis's opt-out; it silences all five on 11a and changes nothing on 09.

### CI and tools

- `flake.nix` `checkPhase`: the `odin check ... -target:windows_amd64` line and its two comment lines go.
- New `tools/ci_download_odin.sh`, mode 755, used by the `windows` and `android` jobs:
  ```bash
  #!/usr/bin/env bash
  # The latest Odin release for a CI job (work item 0315, doc/build.md, CI):
  # the release's odin-<platform>-<tag> archive, checked against the
  # SHA-256 digest GitHub records for the asset (the release publishes no
  # checksum file), unpacked under RUNNER_TEMP, and ODIN=<its odin> added
  # to GITHUB_ENV. Needs gh with GH_TOKEN, curl, sha256sum, and 7z or tar.
  #   tools/ci_download_odin.sh windows-amd64
  #   tools/ci_download_odin.sh linux-amd64
  set -euo pipefail

  platform="$1"
  downloads="$RUNNER_TEMP"
  if command -v cygpath > /dev/null 2>&1; then
  	downloads="$(cygpath -u "$RUNNER_TEMP")"
  fi
  assets="$(gh api repos/odin-lang/Odin/releases/latest --jq '.tag_name as $tag | .assets[] | [$tag, .name, .digest, .browser_download_url] | @tsv')"
  matches="$(awk -F '\t' -v prefix="odin-$platform-" 'index($2, prefix) == 1' <<< "$assets")"
  if [ -z "$matches" ] || [ "$(wc -l <<< "$matches")" -ne 1 ]; then
  	echo "expected one odin-$platform- asset in the latest Odin release, which has:" >&2
  	cut -f 1,2 <<< "$assets" >&2
  	exit 1
  fi
  IFS=$'\t' read -r tag name digest url <<< "$matches"
  if [ "${digest#sha256:}" = "$digest" ]; then
  	echo "$name has no SHA-256 digest on GitHub: '$digest'" >&2
  	exit 1
  fi
  archive="$downloads/$name"
  curl --fail --location --silent --show-error --output "$archive" "$url"
  echo "${digest#sha256:}  $archive" | sha256sum --check -
  mkdir -p "$downloads/odin"
  case "$name" in
  	*.zip) 7z x -o"$downloads/odin" "$archive" > /dev/null ;;
  	*.tar.gz) tar -xzf "$archive" -C "$downloads/odin" ;;
  	*) echo "unknown archive type: $name" >&2; exit 1 ;;
  esac
  executable_name=odin
  if [[ "$platform" == windows-* ]]; then
  	executable_name=odin.exe
  fi
  odin_executable="$(find "$downloads/odin" -name "$executable_name" -type f -print -quit)"
  if [ -z "$odin_executable" ]; then
  	echo "$executable_name not found in $name" >&2
  	exit 1
  fi
  echo "ODIN=$odin_executable" >> "$GITHUB_ENV"
  echo "Odin $tag ($name)"
  "$odin_executable" version
  ```
- `.github/workflows/ci.yml`:
  - `windows`: the `env` keeps only `GH_TOKEN: ${{ github.token }}`; the Odin step becomes `name: Download the latest Odin release`, `run: tools/ci_download_odin.sh windows-amd64`; the SDL3 step:
    ```yaml
          - name: Download the latest SDL3 release and give Odin its SDL3.lib
            run: |
              downloads="$(cygpath -u "$RUNNER_TEMP")"
              # The highest release-3.x.y by version, not the newest by date:
              # SDL 2 releases share the repository, and an older 3.x line can
              # publish after a newer one.
              tag="$(gh api 'repos/libsdl-org/SDL/releases?per_page=100' --jq '[.[] | select(.draft == false and .prerelease == false and (.tag_name | test("^release-3\\.[0-9]+\\.[0-9]+$")))] | max_by(.tag_name | ltrimstr("release-") | split(".") | map(tonumber)) | .tag_name')"
              version="${tag#release-}"
              asset="SDL3-devel-$version-VC.zip"
              digest="$(gh api "repos/libsdl-org/SDL/releases/tags/$tag" --jq ".assets[] | select(.name == \"$asset\") | .digest")"
              if [ "${digest#sha256:}" = "$digest" ]; then
                echo "no SHA-256 digest for $asset in $tag: '$digest'" >&2
                exit 1
              fi
              curl --fail --location --silent --show-error --output "$downloads/sdl3.zip" "https://github.com/libsdl-org/SDL/releases/download/$tag/$asset"
              echo "${digest#sha256:}  $downloads/sdl3.zip" | sha256sum --check -
              7z x -o"$downloads/sdl3" "$downloads/sdl3.zip" > /dev/null
              cp "$downloads/sdl3/SDL3-$version/lib/x64/SDL3.lib" "$(dirname "$ODIN")/vendor/sdl3/"
              echo "SDL3_DLL=$downloads/sdl3/SDL3-$version/lib/x64/SDL3.dll" >> "$GITHUB_ENV"
              echo "SDL3 $version"
    ```
  - `android`: `env` becomes `GH_TOKEN: ${{ github.token }}`; the Odin step `name: Download the latest Odin release`, `run: tools/ci_download_odin.sh linux-amd64`; the comment above the job: `tools/android_env.sh` takes the runner's newest NDK and build-tools, the bundler its newest platform, and the runner's Java runs apksigner.
  - `nix`: unchanged.
- `tools/android_env.sh`: the header says the NDK and build-tools float (CI the runner's newest, the couch the newest `tools/android_toolchain.sh` installed) and the bundler picks build-tools and platform itself. `ODIN_ANDROID_SDK` moves above the versions; `ANDROID_PLATFORM_VERSION` becomes `ANDROID_TARGET_SDK_VERSION=34` with decision 5's reason; `ANDROID_API_LEVEL=29` with the ELF thread local storage reason and "raylib's archive is built for 28, which links into a higher level"; the export line follows the names:
  ```bash
  ANDROID_NDK_VERSION="$(ls -1 "$ODIN_ANDROID_SDK/ndk" 2> /dev/null | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -n 1 || true)"
  ANDROID_BUILD_TOOLS_VERSION="$(ls -1 "$ODIN_ANDROID_SDK/build-tools" 2> /dev/null | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -n 1 || true)"
  ```
  (`|| true`: the file is sourced under `set -euo pipefail`, and the installer sources it before anything is installed.)
- `tools/android_toolchain.sh`: the header names the floating packages; the bootstrap zip keeps its name and SHA-256, its comment gaining decision 5's reason; `install_packages` installs `platform-tools`, `build-tools/<newest>`, `platforms/android-$ANDROID_TARGET_SDK_VERSION` and `ndk/<newest>`, failing with a message when either newest is empty, through:
  ```bash
  # The newest stable version of an SDK package in sdkmanager's list, such
  # as ndk or build-tools (0315); rc versions do not match.
  newest_package_version() {
  	"$sdkmanager" --sdk_root="$ODIN_ANDROID_SDK" --list \
  		| sed -n -E "s/^ *$1;([0-9]+(\.[0-9]+)*) .*/\1/p" | sort -V | tail -n 1
  }
  ```
- `tools/build_raylib.sh`: above `raylib_tag="6.0"`, decision 6's reason in three lines.

### Docs

- `CLAUDE.md`, Stack, first line: the toolchain is `~/opt/odin`, a link to the release in use (dev-2026-11a since 2026-11-07, 0315), another release only with the user's approval; CI's `windows` and `android` jobs take the latest release and the `nix` job nixpkgs' Odin, which may lag, so the code compiles on both ([doc/build.md](doc/build.md), CI).
- `doc/build.md`: the toolchain table's Odin row (dev-2026-11a, nightly 9a69916, `~/opt/odin-linux-amd64-nightly+2026-11-03` linked as `~/opt/odin`, the asset `odin-linux-amd64-dev-2026-11a.tar.gz`) and raylib row (pinned, the reason in `tools/build_raylib.sh`); The shared collection: the binding is redone after a raylib upgrade, not an Odin one; build.sh: `check-windows` is guarded on every push by the `windows` job's native build; Nix: no Windows check; CI: the table's `nix` row, then bullets for each job's Odin (nix: nixpkgs-unstable's, dev-2026-10 on 2026-11-07; windows and android: the latest release through `tools/ci_download_odin.sh`, digest checked), the SDL3 rule, the pins left and where their reasons stand (raylib, the target SDK, the command line tools zip), the actions floating within their major tags; Windows: the job bullet (the latest Odin and SDL3 3.x, digest checked) and one line that radlink is Odin's default Windows linker since dev-2026-10 (Odin #7739).
- `doc/android.md`: Toolchain (the table becomes the floating rule, the target SDK 34 and the minimum 29 with their reasons, Java without a version; the `android_env.sh` and `android_toolchain.sh` bullets with the new names and packages); raylib for Android (the archive at 28 links into 29); Entry point ("Facts checked in Odin dev-2026-11a": the INIT and FINI entries, `__wrap_main` and the `@(init)` note, raylib's glue kept by `-u ANativeActivity_onCreate`, no `main` on Android and `main_desktop.odin`); One process, many launches (the start at load from 11, the cleanup still never); Link (the `-u` line, Odin adds `--no-undefined` itself from 11); Building the APK (`check-android`'s flags, step 1's level 29 and path, step 4's `-out`, the bundler bullet replacing the aapt one and the `lib/lib` gotcha, the export check); CI and installing (the latest Odin through the script, the runner's newest NDK and build-tools).
- `doc/code_map.md`, loop: the `main.odin` line names `game_main`; a `main_desktop.odin` line (`main` everywhere but Android); `main_android.odin` wraps `game_main`.
- `shared/raylib/README.md`: "After an Odin upgrade" becomes "After a raylib upgrade", the binding copied from an Odin release whose `vendor/raylib` binds that raylib (dev-2026-11 binds 6.2); an Odin upgrade alone keeps the copy (0315). The Android archive line: built for API level 28, below the game's 29 ([doc/android.md](../../doc/android.md)).

### Verify

- Implementer and verifier, with the 11a `ODIN`: `./build.sh check`, `check-windows`, `check-android` and `test` pass with no warning; `./build.sh check` and `./build.sh test` also with the default dev-2026-09; `distrobox enter mine-oh-belowed-android -- env ODIN=<11a> ./build.sh android` builds the APK, the export check passes, the newest build-tools' `aapt2 dump badging` names `sdkVersion:'29'`, `targetSdkVersion:'34'` and `native-code: 'arm64-v8a'`, and `apksigner verify` passes; `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md` and `python3 tools/check_dead_code.py`.
- `bash -n tools/ci_download_odin.sh`; its `gh api` and `awk` lines, and the SDL3 step's filter, run read-only against the live API and name dev-2026-11a's two assets and release-3.4.20.
- `tools/android_toolchain.sh` is never run (it installs; the user decides when); `newest_package_version`'s sed runs over `sdkmanager --list` in the container (read-only) and names the newest ndk and build-tools.
- Hand-back check: no line applies (no freed memory, file write, parsed number, save layout, shared budget, growing list, audit case or test state).
- Main agent: CI green on all three jobs, the logs naming dev-2026-11a, SDL3 3.4.20 and the runner's newest NDK; `tools/wine_smoke_test.sh` on the Windows artifact (radlink linked now); the CI APK on the phone installs over the last one, starts, starts again after Back, and Quit ends it; the link switch, then the suite on `main`.

### Questions for the main agent

1. Android 9 is dropped by the toolchain (decision 5): whether the user needs telling before the APK lands.
2. raylib 6.2 (decision 6) as a new item: rebuild the three archives, drop the third patch, the binding from 11a's `vendor:raylib`.
3. The libc rule: "never in a file the Windows build compiles", the `core:sys/posix` rule `test_static_runtime_imports_stay_out_of_windows` already enforces, would let the non-Windows branch call `libc.vsnprintf`, which takes `^va_list` on every release and needs no architecture switch. Kept out as instructed.
4. The `windows` and `android` artifacts are built with an Odin the suite runs on only locally, and the `nix` job's Odin lags: a CI suite run on the latest release is not part of this item.

### Main agent's decisions (2026-11-07)

- Android 9 and older are dropped with the minimum level 29, as the toolchain requires. The user is asked before the landing. The implementation goes ahead.
- raylib 6.2 is 0319, its own item.
- The libc rule stays as it is, and the architecture switch for `vsnprintf` ships.
- No CI suite run on the latest release: the local suite runs on it, since `~/opt/odin` follows the latest release from this landing on, and the `nix` job tests nixpkgs' Odin.
- Landing order: 0307, this item, then 0316. The `~/opt/odin` link is switched at this item's landing, before the suite on `main`.
