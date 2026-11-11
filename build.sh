#!/usr/bin/env bash
# Build, check or test the game. See doc/build.md.
#   ./build.sh [debug]   debug build to build/mine-oh-belowed (default)
#   ./build.sh release   optimised build to build/mine-oh-belowed
# bin/ is reserved for the installed play build, see tools/install_play_build.sh.
#   ./build.sh check     odin check src -vet -strict-style
#   ./build.sh check-windows
#                        the same check for the windows_amd64 target, on
#                        any host (work item 0102)
#   ./build.sh test [all|unit|slow|quick] [files or tests] [flags]
#                        the tests of a tier, all by default (work item
#                        0316, doc/build.md, Test tiers)
#   ./build.sh nightly   the report tests and the factory benchmark,
#                        optimised and one at a time, 03:00 to 06:00
#                        Europe/Stockholm under ~/benchmark.lock
#   ./build.sh bench     the factory benchmark only, the same guard
#   ./build.sh frame-profile [view ...]
#                        the release build, then the frame table of
#                        tools/frame_profile.py under gamescope, the same
#                        guard (work item 0342, doc/build.md, Frame
#                        profile)
#   ./build.sh check-android
#                        the same check for Android arm64 (work item 0114),
#                        with tools/android_env.sh sourced
#   ./build.sh model-check [machine]
#                        the debug build, then --model-check (all by
#                        default; work item 0207, doc/build.md, The
#                        workbench)
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
	"$odin" test src -all-packages "$collection" "${platform_flags[@]}" "$@"
}

# The tests of a tier (doc/build.md, Test tiers): arguments starting with
# - are odin flags, the rest select the tests of quick. The binary is
# built like odin test builds it and run from the repository root, its
# output through the filter that times each test and fails an unmarked
# slow one. all passes no names, so it runs what odin test runs. Paths
# given to quick that select no test build and run nothing.
run_test_tier() {
	local tier="$1" argument listing
	shift
	local flags=() selectors=() names=()
	for argument in "$@"; do
		case "$argument" in
			-*ODIN_TEST_NAMES*)
				echo "name the tests with ./build.sh test quick" >&2
				exit 2
				;;
			-*) flags+=("$argument") ;;
			*) selectors+=("$argument") ;;
		esac
	done
	if [ "${#selectors[@]}" -gt 0 ] && [ "$tier" != quick ]; then
		echo "./build.sh test $tier takes no files or tests, name them with ./build.sh test quick" >&2
		exit 2
	fi
	# unit and quick build unoptimised (0318): their compile outweighs
	# their run. A given -o flag stays alone, odin refuses a second.
	if [ "$tier" = unit ] || [ "$tier" = quick ]; then
		case " ${flags[*]-} " in
			*" -o:"*) ;;
			*) flags+=(-o:none) ;;
		esac
	fi
	set_platform_flags
	if [ "$tier" != all ]; then
		listing="$(python3 tools/test_tiers.py arguments "$tier" "${selectors[@]}")"
		if [ -z "$listing" ]; then
			return 0
		fi
		mapfile -t names <<< "$listing"
	fi
	mkdir -p "$repository_root/build"
	"$odin" build src -all-packages -build-mode:test "$collection" "${platform_flags[@]}" \
		-define:ODIN_TEST_LOG_STATE_CHANGES=true "${flags[@]}" -out:"$repository_root/build/mine-oh-belowed-tests"
	"$repository_root/build/mine-oh-belowed-tests" "${names[@]}" 2>&1 | python3 tools/test_tiers.py filter "$tier"
}

# The pid a lock file names, empty when it names none or is gone.
lock_pid() {
	sed -n 's/^pid=//p' "$1" 2>/dev/null || true
}

# Removes a lock read as stale without ever removing a live one. The lock
# is renamed to a name of this shell's own, so of two guards that read
# the same stale lock only one takes it, and its pid is read again there:
# another guard may have replaced the stale lock with its own meanwhile.
# A live lock goes back through a hard link, which fails rather than
# overwrite a lock that took the name in between.
remove_stale_lock() {
	local lock="$1" claim="$1.claim.$$" claimed_pid
	mv "$lock" "$claim" 2>/dev/null || return 0
	claimed_pid="$(lock_pid "$claim")"
	if [ -n "$claimed_pid" ] && ! kill -0 "$claimed_pid" 2>/dev/null; then
		echo "the lock is stale (pid $claimed_pid is gone), removing it" >&2
		rm -f "$claim"
	elif ln "$claim" "$lock" 2>/dev/null; then
		rm -f "$claim"
	else
		echo "a live lock (pid $claimed_pid) was taken aside as a new lock appeared, left at $claim" >&2
	fi
}

# On exit, the lock goes only while it is still this shell's.
release_benchmark_lock() {
	if [ "$(lock_pid "$HOME/benchmark.lock")" = "$$" ]; then
		rm -f "$HOME/benchmark.lock"
	fi
}

# A benchmark runs only from 03:00 to 06:00 Europe/Stockholm, when nobody
# uses the machine, and holds ~/benchmark.lock so no two benchmarks of any
# project run at once. A lock whose process is gone is stale and removed,
# a live one is waited for.
guard_benchmark() {
	local command="$1" expected_minutes="$2" hour lock_pid
	local lock="$HOME/benchmark.lock"
	while true; do
		hour="$(TZ=Europe/Stockholm date +%H)"
		case "$hour" in
			03 | 04 | 05) ;;
			*)
				echo "$command is a benchmark and runs only from 03:00 to 06:00 Europe/Stockholm, where the hour is $hour" >&2
				exit 2
				;;
		esac
		if (set -o noclobber; printf '%s\n' "pid=$$" "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
			"expected_minutes=$expected_minutes" "cwd=$repository_root" "project=mine-oh-belowed" \
			"command=$command" "session=${CLAUDE_CODE_SESSION_ID:-none}" \
			"note=keep the machine idle: an -o:speed build and timed runs" > "$lock") 2>/dev/null; then
			trap release_benchmark_lock EXIT
			return
		fi
		lock_pid="$(lock_pid "$lock")"
		cat "$lock" >&2 2>/dev/null || continue
		if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
			remove_stale_lock "$lock"
			continue
		fi
		echo "waiting for the benchmark above to end" >&2
		sleep 60
	done
}

# The report tests (behind their when NAME blocks) with every define, and
# the factory benchmark, optimised, on one runner thread so no two of
# them run side by side and skew each other's timings.
nightly() {
	guard_benchmark "./build.sh nightly" 45
	local listing defines=()
	listing="$(python3 tools/test_tiers.py defines)"
	if [ -n "$listing" ]; then
		mapfile -t defines <<< "$listing"
	fi
	run_test_tier nightly -o:speed -define:ODIN_TEST_THREADS=1 "${defines[@]}"
}

# The workbench's checks of the models (work item 0207), from the
# repository root so the game finds data/.
model_check() {
	build -debug
	cd "$repository_root"
	"$output" --model-check="$1"
}

android_container_name=mine-oh-belowed-android
android_directory="$repository_root/build/android"
android_bundle="$android_directory/bundle"

check_android() {
	. "$repository_root/tools/android_env.sh"
	"$odin" check src "$collection" -target:linux_arm64 -subtarget:android -minimum-os-version:"$ANDROID_API_LEVEL" -no-entry-point -vet -strict-style
}

# The bundle layout odin bundle android packages (doc/android.md, Building
# the APK): lib/arm64-v8a/libmain.so lands at the same path in the APK,
# data/ goes to the assets with the list of its files (the asset manager
# cannot list directories), the manifest gets the version and the SDK
# levels.
# The link: --no-undefined, since a shared library otherwise links with
# undefined symbols and Android's loader refuses it on the phone.
# -u ANativeActivity_onCreate keeps raylib's copy of the NDK's glue, the
# activity's entry: from Odin dev-2026-11 nothing else references it, and
# a library that does not export it cannot start (0315).
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
	android_linker_flags="-Wl,--no-undefined -Wl,-u,ANativeActivity_onCreate -L$android_directory/linker-shims -Wl,--wrap=main -Wl,--wrap=fopen"
	for name in __errno_location pthread_setcancelstate pthread_setcanceltype backtrace backtrace_symbols backtrace_symbols_fd; do
		android_linker_flags+=" -Wl,--wrap=$name"
	done
	build_info="$(build_commit) $(date -u +%Y-%m-%dT%H:%MZ)"
	version_code="$(git rev-list --count HEAD)"
	rm -rf "$android_bundle"
	mkdir -p "$android_bundle/lib/arm64-v8a" "$android_bundle/assets" "$android_directory/linker-shims"
	printf '!<arch>\n' > "$android_directory/linker-shims/libpthread.a"
	"$odin" build src "$collection" -target:linux_arm64 -subtarget:android \
		-minimum-os-version:"$ANDROID_API_LEVEL" -build-mode:shared -no-entry-point \
		-extra-linker-flags:"$android_linker_flags" -o:speed -vet -strict-style \
		-define:BUILD_INFO="$build_info" -out:"$android_bundle/lib/arm64-v8a/libmain.so"
	local exports
	exports="$("$ODIN_ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm" -D --defined-only "$android_bundle/lib/arm64-v8a/libmain.so")"
	if [[ "$exports" != *" T ANativeActivity_onCreate"* ]]; then
		echo "libmain.so exports no ANativeActivity_onCreate, so Android cannot start it" >&2
		exit 1
	fi
	cp -r data "$android_bundle/assets/data"
	find data -type f | sort > "$android_bundle/assets/data_files.txt"
	cp -r tools/android/res "$android_bundle/res"
	sed -e "s|@VERSION_CODE@|$version_code|" -e "s|@VERSION_NAME@|$build_info|" \
		-e "s|@MIN_SDK_VERSION@|$ANDROID_API_LEVEL|" -e "s|@TARGET_SDK_VERSION@|$ANDROID_TARGET_SDK_VERSION|" \
		tools/android/AndroidManifest.xml > "$android_bundle/AndroidManifest.xml"
	cd "$android_directory"
	rm -f mine-oh-belowed.apk mine-oh-belowed.apk.idsig
	"$odin" bundle android bundle -out:"$android_directory/mine-oh-belowed.apk" \
		-android-keystore:"$repository_root/tools/android/debug.keystore" \
		-android-keystore-alias:androiddebugkey -android-keystore-password:android \
		-minimum-os-version:"$ANDROID_API_LEVEL"
	rm -f mine-oh-belowed.apk.idsig
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
	test)
		shift
		tier=all
		case "${1:-}" in
			all | unit | slow | quick)
				tier="$1"
				shift
				;;
		esac
		run_test_tier "$tier" "$@"
		;;
	nightly) nightly ;;
	bench)
		guard_benchmark "./build.sh bench" 40
		run_tests -o:speed -define:ODIN_TEST_NAMES=game.test_factory_benchmark
		;;
	frame-profile)
		# Not exec: the script checks that the lock names this shell, and the
		# shell's trap releases it.
		shift
		guard_benchmark "./build.sh frame-profile" 40
		build "${release_flags[@]}"
		python3 tools/frame_profile.py "$@"
		;;
	check-android) check_android ;;
	android) build_android ;;
	model-check) model_check "${2:-all}" ;;
	*)
		echo "usage: $0 [debug|release|check|check-windows|test|nightly|bench|frame-profile|check-android|android|model-check]" >&2
		exit 2
		;;
esac
