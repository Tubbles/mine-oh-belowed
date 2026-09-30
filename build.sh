#!/usr/bin/env bash
# Build, check or test the game. See doc/build.md.
#   ./build.sh [debug]   debug build to build/mine-oh-belowed (default)
#   ./build.sh release   optimised build to build/mine-oh-belowed
# bin/ is reserved for the installed play build, see tools/install_play_build.sh.
#   ./build.sh check     odin check src -vet -strict-style
#   ./build.sh check-windows
#                        the same check for the windows_amd64 target, on
#                        any host (work item 0102)
#   ./build.sh test      odin test src
#   ./build.sh bench     the factory benchmark test, optimised, with the
#                        size 4 budget (work item 0050)
#   ./build.sh check-android
#                        the same check for Android arm64 (work item 0114),
#                        with tools/android_env.sh sourced
#   ./build.sh android   the signed APK build/android/mine-oh-belowed.apk
#                        (work item 0114); apksigner needs Java, so without
#                        java on the PATH it re-runs itself inside the
#                        distrobox mine-oh-belowed-android (work item 0113)
# Every command passes the shared collection, which holds the raylib
# binding and the library tools/build_raylib.sh builds (work item 0085),
# so a bare odin check src no longer compiles.
# On a Windows host under Git Bash (CI, work item 0102) ODIN names
# odin.exe, the output is build/mine-oh-belowed.exe, there are no linker
# shims, and release links for the windows subsystem so no console window
# opens beside the game.
set -euo pipefail

case "$(uname -s)" in
	MINGW* | MSYS*) windows_host=true ;;
	*) windows_host=false ;;
esac

odin="${ODIN:-$HOME/opt/odin/odin}"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_suffix=""
if [ "$windows_host" = true ]; then
	# C:/a/b rather than /c/a/b: odin.exe is no MSYS program, so the paths
	# it gets inside -collection: and -out: must not rely on Git Bash
	# converting them.
	repository_root="$(cygpath -m "$repository_root")"
	output_suffix=".exe"
fi
shim_directory="$repository_root/tmp/linker-shims"
output="$repository_root/build/mine-oh-belowed$output_suffix"
mode="${1:-debug}"
collection="-collection:shared=$repository_root/shared"

cd "$repository_root"

# Bazzite ships runtime libraries without the unversioned development
# symlinks the linker looks for, so point it at a directory of our own.
create_linker_shims() {
	mkdir -p "$shim_directory"
	ln -sfn /usr/lib64/libX11.so.6 "$shim_directory/libX11.so"
	ln -sfn /usr/lib64/libSDL3.so.0 "$shim_directory/libSDL3.so"
}

# The build stamp the game shows (title screen, pause menu, log header,
# --version): the short commit, "+dirty" with uncommitted changes, and the
# UTC build time, in one define so an all digit value is never read as a
# number. tools/install_play_build.sh builds from a git archive without
# .git and passes the commit in MINE_OH_BELOWED_COMMIT.
build_commit() {
	if [ -n "${MINE_OH_BELOWED_COMMIT:-}" ]; then
		printf '%s' "$MINE_OH_BELOWED_COMMIT"
		return
	fi
	local commit
	commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
	if [ "$commit" != unknown ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
		commit="$commit+dirty"
	fi
	printf '%s' "$commit"
}

# The host's linker flags: the shims on Linux, nothing on Windows.
set_platform_flags() {
	platform_flags=()
	if [ "$windows_host" = false ]; then
		create_linker_shims
		platform_flags=(-extra-linker-flags:"-L$shim_directory")
	fi
}

build() {
	set_platform_flags
	mkdir -p "$(dirname "$output")"
	"$odin" build src -out:"$output" "$collection" -vet -strict-style \
		-define:BUILD_INFO="$(build_commit) $(date -u +%Y-%m-%dT%H:%MZ)" \
		"${platform_flags[@]}" "$@"
}

# Odin links a foreign library only when a reachable procedure uses it,
# so the test binary links raylib (and with it X11) as soon as one test
# reaches a procedure that loads or draws through it; the shims serve
# the test link like the build.
run_tests() {
	set_platform_flags
	"$odin" test src "$collection" "${platform_flags[@]}" "$@"
}

android_container_name=mine-oh-belowed-android
android_directory="$repository_root/build/android"
android_bundle="$android_directory/bundle"

check_android() {
	. "$repository_root/tools/android_env.sh"
	"$odin" check src "$collection" -target:linux_arm64 -subtarget:android -vet -strict-style
}

# The bundle layout odin bundle android packages (doc/build.md, Android):
# lib/lib/arm64-v8a/libmain.so lands at lib/arm64-v8a/libmain.so in the
# APK, data/ goes to the assets with the list of its files (the asset
# manager cannot list directories), the manifest gets the version.
# The link: --no-undefined, since a shared library otherwise links with
# undefined symbols and Android's loader refuses it on the phone.
# --wrap=main reaches the game's entry point. --wrap=fopen routes raylib's
# file reads through its asset reader (rcore_android.c); a static archive
# cannot apply the wrap itself, and without it __real_fopen stays
# undefined. The other wraps send glibc functions bionic lacks to
# src/android_libc/. Odin's core:thread and core:sys/posix link
# system:pthread on Linux, but Android keeps the pthread functions in libc
# and the NDK has no libpthread, so an empty archive stands in.
build_android() {
	if ! command -v java >/dev/null 2>&1; then
		exec distrobox enter "$android_container_name" -- "$repository_root/build.sh" android
	fi
	. "$repository_root/tools/android_env.sh"
	local build_info version_code android_linker_flags
	android_linker_flags="-Wl,--no-undefined -L$android_directory/linker-shims -Wl,--wrap=main -Wl,--wrap=fopen"
	for name in __errno_location pthread_setcancelstate pthread_setcanceltype backtrace backtrace_symbols backtrace_symbols_fd; do
		android_linker_flags+=" -Wl,--wrap=$name"
	done
	build_info="$(build_commit) $(date -u +%Y-%m-%dT%H:%MZ)"
	version_code="$(git rev-list --count HEAD)"
	rm -rf "$android_bundle"
	mkdir -p "$android_bundle/lib/lib/arm64-v8a" "$android_bundle/assets" "$android_directory/linker-shims"
	printf '!<arch>\n' > "$android_directory/linker-shims/libpthread.a"
	"$odin" build src "$collection" -target:linux_arm64 -subtarget:android \
		-minimum-os-version:"$ANDROID_API_LEVEL" -build-mode:shared -no-entry-point \
		-extra-linker-flags:"$android_linker_flags" -o:speed -vet -strict-style \
		-define:BUILD_INFO="$build_info" -out:"$android_bundle/lib/lib/arm64-v8a/libmain.so"
	cp -r data "$android_bundle/assets/data"
	find data -type f | sort > "$android_bundle/assets/data_files.txt"
	cp -r tools/android/res "$android_bundle/res"
	sed -e "s|@VERSION_CODE@|$version_code|" -e "s|@VERSION_NAME@|$build_info|" \
		tools/android/AndroidManifest.xml > "$android_bundle/AndroidManifest.xml"
	cd "$android_directory"
	rm -f test.apk test.apk-build test.apk.idsig mine-oh-belowed.apk
	"$odin" bundle android bundle \
		-android-keystore:"$repository_root/tools/android/debug.keystore" \
		-android-keystore-alias:androiddebugkey -android-keystore-password:android \
		-minimum-os-version:"$ANDROID_API_LEVEL"
	mv test.apk mine-oh-belowed.apk
	rm -f test.apk-build test.apk.idsig
	echo "$android_directory/mine-oh-belowed.apk: $(wc -c < mine-oh-belowed.apk) bytes (version code $version_code, $build_info)"
}

release_flags=(-o:speed)
if [ "$windows_host" = true ]; then
	release_flags+=(-subsystem:windows)
fi

case "$mode" in
	debug) build -debug ;;
	release) build "${release_flags[@]}" ;;
	check) "$odin" check src "$collection" -vet -strict-style ;;
	check-windows) "$odin" check src "$collection" -target:windows_amd64 -vet -strict-style ;;
	test) run_tests ;;
	bench) run_tests -o:speed -define:ODIN_TEST_NAMES=game.test_factory_benchmark ;;
	check-android) check_android ;;
	android) build_android ;;
	*)
		echo "usage: $0 [debug|release|check|check-windows|test|bench|check-android|android]" >&2
		exit 2
		;;
esac
