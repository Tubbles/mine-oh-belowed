#!/usr/bin/env bash
# Build, check or test the game. See doc/build.md.
#   ./build.sh [debug]   debug build to build/mine-oh-belowed (default)
#   ./build.sh release   optimised build to build/mine-oh-belowed
# bin/ is reserved for the installed play build, see tools/install_play_build.sh.
#   ./build.sh check     odin check src -vet -strict-style
#   ./build.sh test      odin test src
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

build() {
	create_linker_shims
	mkdir -p "$(dirname "$output")"
	"$odin" build src -out:"$output" -vet -strict-style \
		-extra-linker-flags:"-L$shim_directory" "$@"
}

case "$mode" in
	debug) build -debug ;;
	release) build -o:speed ;;
	check) "$odin" check src -vet -strict-style ;;
	test) "$odin" test src ;;
	*)
		echo "usage: $0 [debug|release|check|test]" >&2
		exit 2
		;;
esac
