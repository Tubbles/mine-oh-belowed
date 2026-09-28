#!/usr/bin/env bash
# Build, check or test the game. See doc/build.md.
#   ./build.sh [debug]   debug build to build/mine-oh-belowed (default)
#   ./build.sh release   optimised build to build/mine-oh-belowed
# bin/ is reserved for the installed play build, see tools/install_play_build.sh.
#   ./build.sh check     odin check src -vet -strict-style
#   ./build.sh test      odin test src
#   ./build.sh bench     the factory benchmark test, optimised, with the
#                        size 4 budget (work item 0050)
set -euo pipefail

odin="${ODIN:-$HOME/opt/odin/odin}"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shim_directory="$repository_root/tmp/linker-shims"
output="$repository_root/build/mine-oh-belowed"
mode="${1:-debug}"

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
	create_linker_shims
	mkdir -p "$(dirname "$output")"
	"$odin" build src -out:"$output" -vet -strict-style \
		-define:BUILD_INFO="$(build_commit) $(date -u +%Y-%m-%dT%H:%MZ)" \
		-extra-linker-flags:"-L$shim_directory" "$@"
}

case "$mode" in
	debug) build -debug ;;
	release) build -o:speed ;;
	check) "$odin" check src -vet -strict-style ;;
	test) "$odin" test src ;;
	bench) "$odin" test src -o:speed -define:ODIN_TEST_NAMES=game.test_factory_benchmark ;;
	*)
		echo "usage: $0 [debug|release|check|test|bench]" >&2
		exit 2
		;;
esac
