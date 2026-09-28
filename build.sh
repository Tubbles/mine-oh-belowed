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

build() {
	local platform_flags=()
	if [ "$windows_host" = false ]; then
		create_linker_shims
		platform_flags=(-extra-linker-flags:"-L$shim_directory")
	fi
	mkdir -p "$(dirname "$output")"
	"$odin" build src -out:"$output" "$collection" -vet -strict-style \
		-define:BUILD_INFO="$(build_commit) $(date -u +%Y-%m-%dT%H:%MZ)" \
		"${platform_flags[@]}" "$@"
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
	test) "$odin" test src "$collection" ;;
	bench) "$odin" test src "$collection" -o:speed -define:ODIN_TEST_NAMES=game.test_factory_benchmark ;;
	*)
		echo "usage: $0 [debug|release|check|check-windows|test|bench]" >&2
		exit 2
		;;
esac
