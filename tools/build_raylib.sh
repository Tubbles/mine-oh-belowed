#!/usr/bin/env bash
# Build raylib 6.0 from the upstream tag with both GLFW backends (Wayland
# and X11, GLFW picks at run time) into shared/raylib/linux/
# libraylib.a and rewrite the build record in shared/raylib/
# README.md. Work item 0085, see doc/build.md.
#   tools/build_raylib.sh          build inside the distrobox
#                                  mine-oh-belowed-raylib (Fedora 44),
#                                  created on first use
#   tools/build_raylib.sh --host   build on this machine, which needs git,
#                                  cmake, a C compiler and the Wayland,
#                                  xkbcommon, libdecor and X11 headers
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
raylib_tag="6.0"
raylib_url="https://github.com/raysan5/raylib"
source_directory="$repository_root/tmp/raylib-src"
build_directory="$repository_root/tmp/raylib-build"
collection_directory="$repository_root/shared/raylib"
container_name="mine-oh-belowed-raylib"
container_image="registry.fedoraproject.org/fedora-toolbox:44"
container_packages="cmake gcc gcc-c++ make git wayland-devel wayland-protocols-devel libxkbcommon-devel libdecor-devel mesa-libGL-devel libX11-devel libXrandr-devel libXinerama-devel libXcursor-devel libXi-devel libXext-devel"

fetch_source() {
	rm -rf "$source_directory"
	git clone --quiet --depth 1 --branch "$raylib_tag" "$raylib_url" "$source_directory"
}

# GLFW_BUILD_WAYLAND and GLFW_BUILD_X11 are GLFW's own options, raylib's
# src/external/glfw/CMakeLists.txt reads them. Both on: GLFW 3.4 loads
# libwayland-client, libwayland-cursor, libwayland-egl, libxkbcommon and
# libdecor with dlopen, so the link needs nothing new. The generator is
# named so a CMAKE_GENERATOR from the environment (Ninja, which the
# container lacks) does not apply.
configure_and_build() {
	rm -rf "$build_directory"
	cmake -S "$source_directory" -B "$build_directory" -G "Unix Makefiles" \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=OFF \
		-DBUILD_EXAMPLES=OFF \
		-DPLATFORM=Desktop \
		-DGLFW_BUILD_WAYLAND=ON \
		-DGLFW_BUILD_X11=ON \
		-DCMAKE_POSITION_INDEPENDENT_CODE=ON
	cmake --build "$build_directory" --parallel 2
}

write_build_record() {
	local commit size
	commit="$(git -C "$source_directory" rev-parse HEAD)"
	size="$(stat -c %s "$collection_directory/linux/libraylib.a")"
	sed -i '/^<!-- build record -->$/,$d' "$collection_directory/README.md"
	cat >> "$collection_directory/README.md" <<RECORD
<!-- build record -->
- raylib tag: $raylib_tag ($raylib_url), commit $commit
- cmake flags: -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF -DPLATFORM=Desktop -DGLFW_BUILD_WAYLAND=ON -DGLFW_BUILD_X11=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
- compiler: $(cc --version | head -n 1)
- built: $(date -u +%Y-%m-%dT%H:%MZ)
- archive: linux/libraylib.a, $size bytes
RECORD
}

build_on_host() {
	fetch_source
	configure_and_build
	mkdir -p "$collection_directory/linux"
	cp "$build_directory/raylib/libraylib.a" "$collection_directory/linux/libraylib.a"
	write_build_record
	echo "built $collection_directory/linux/libraylib.a"
}

# The home directory is shared with the container, so the same script runs
# inside it with --host.
build_in_container() {
	if ! distrobox list --no-color | grep -q " $container_name "; then
		distrobox create --yes --name "$container_name" --image "$container_image" \
			--additional-packages "$container_packages"
	fi
	distrobox enter "$container_name" -- "$repository_root/tools/build_raylib.sh" --host
}

case "${1:-}" in
	--host) build_on_host ;;
	"") build_in_container ;;
	*)
		echo "usage: $0 [--host]" >&2
		exit 2
		;;
esac
