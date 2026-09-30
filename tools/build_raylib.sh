#!/usr/bin/env bash
# Build raylib 6.0 from the upstream tag into the shared collection and
# rewrite that platform's build record in shared/raylib/README.md.
# Desktop: both GLFW backends (Wayland and X11, GLFW picks at run time)
# into shared/raylib/linux/libraylib.a, work item 0085. Android: arm64-v8a
# with OpenGL ES 3.0 into shared/raylib/android/libraylib.a, work item
# 0113. See doc/build.md.
#   tools/build_raylib.sh          build inside the distrobox
#                                  mine-oh-belowed-raylib (Fedora 44),
#                                  created on first use
#   tools/build_raylib.sh --host   build on this machine, which needs git,
#                                  cmake, a C compiler and the Wayland,
#                                  xkbcommon, libdecor and X11 headers
#   tools/build_raylib.sh --android
#                                  build inside the distrobox
#                                  mine-oh-belowed-android, after
#                                  tools/android_toolchain.sh (which
#                                  creates it and installs the NDK)
#   tools/build_raylib.sh --android --host
#                                  build on this machine, which needs git,
#                                  cmake, make and the NDK named by
#                                  tools/android_env.sh
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
raylib_tag="6.0"
raylib_url="https://github.com/raysan5/raylib"
source_directory="$repository_root/tmp/raylib-src"
build_directory="$repository_root/tmp/raylib-build"
android_build_directory="$repository_root/tmp/raylib-build-android"
collection_directory="$repository_root/shared/raylib"
container_name="mine-oh-belowed-raylib"
android_container_name="mine-oh-belowed-android"
container_image="registry.fedoraproject.org/fedora-toolbox:44"
container_packages="cmake gcc gcc-c++ make git wayland-devel wayland-protocols-devel libxkbcommon-devel libdecor-devel mesa-libGL-devel libX11-devel libXrandr-devel libXinerama-devel libXcursor-devel libXi-devel libXext-devel"
desktop_record_marker="<!-- build record -->"
android_record_marker="<!-- android build record -->"

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

# rlLoadShaderDefault declares "precision mediump float;" in the OpenGL
# ES 3 default vertex and fragment shaders (kept for WebGL browsers). On
# Mali mediump is 16 bit, so world space positions drawn through raylib's
# batch snap to a coarse grid that shifts as the camera moves (work item
# 0126). Only the two ES3 lines are rewritten, found by their "OpenGL ES3
# (WebGL 2)" comment; the ES2 lines are not compiled for ES 3.0. Anything
# but two rewrites fails, so a raylib upgrade that moves the text is
# noticed. fetch_source clones afresh on every run, so the file is never
# already patched.
patch_default_shader_precision() {
	local header="$source_directory/src/rlgl.h"
	awk '
		/precision mediump float;/ && /OpenGL ES3 \(WebGL 2\)/ {
			sub(/precision mediump float;/, "precision highp float;")
			rewrites++
		}
		{ print }
		END { if (rewrites != 2) exit 1 }
	' "$header" > "$header.new" || {
		echo "rlgl.h: expected two OpenGL ES3 default shader precision lines" >&2
		rm -f "$header.new"
		exit 1
	}
	mv "$header.new" "$header"
}

# raylib's cmake forces OpenGL ES 2.0 for PLATFORM=Android; OPENGL_VERSION
# "ES 3.0" overrides it with a warning ("You are overriding the suggested
# GRAPHICS"), which is expected. The archive holds rcore_android.c with
# android_main, which calls the executable's C main.
android_configure_and_build() {
	rm -rf "$android_build_directory"
	cmake -S "$source_directory" -B "$android_build_directory" -G "Unix Makefiles" \
		-DCMAKE_TOOLCHAIN_FILE="$ODIN_ANDROID_NDK/build/cmake/android.toolchain.cmake" \
		-DANDROID_ABI=arm64-v8a \
		-DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
		-DPLATFORM=Android \
		-DOPENGL_VERSION="ES 3.0" \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=OFF \
		-DBUILD_EXAMPLES=OFF
	cmake --build "$android_build_directory" --parallel 2
}

# Each platform's record starts at its own marker and runs to the next
# record marker or the end of the file; a rewrite removes only its own
# block and appends the new one.
remove_build_record() {
	local marker="$1"
	local readme="$collection_directory/README.md"
	awk -v marker="$marker" '
		$0 == marker { skipping = 1; next }
		skipping && /^<!-- .*build record -->$/ { skipping = 0 }
		!skipping { print }
	' "$readme" > "$readme.new"
	mv "$readme.new" "$readme"
}

write_build_record() {
	local commit size
	commit="$(git -C "$source_directory" rev-parse HEAD)"
	size="$(stat -c %s "$collection_directory/linux/libraylib.a")"
	remove_build_record "$desktop_record_marker"
	cat >> "$collection_directory/README.md" <<RECORD
$desktop_record_marker
- raylib tag: $raylib_tag ($raylib_url), commit $commit
- cmake flags: -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF -DPLATFORM=Desktop -DGLFW_BUILD_WAYLAND=ON -DGLFW_BUILD_X11=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
- compiler: $(cc --version | head -n 1)
- built: $(date -u +%Y-%m-%dT%H:%MZ)
- archive: linux/libraylib.a, $size bytes
RECORD
}

write_android_build_record() {
	local commit size compiler
	commit="$(git -C "$source_directory" rev-parse HEAD)"
	size="$(stat -c %s "$collection_directory/android/libraylib.a")"
	compiler="$("$ODIN_ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" --version | head -n 1)"
	remove_build_record "$android_record_marker"
	cat >> "$collection_directory/README.md" <<RECORD
$android_record_marker
- android raylib tag: $raylib_tag ($raylib_url), commit $commit
- android source patch: src/rlgl.h, the two OpenGL ES3 default shader lines "precision mediump float;" become "precision highp float;" (work item 0126)
- android cmake flags: -G "Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=<ndk>/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$ANDROID_API_LEVEL -DPLATFORM=Android -DOPENGL_VERSION="ES 3.0" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF
- android compiler: NDK $ANDROID_NDK_VERSION, $compiler
- android built: $(date -u +%Y-%m-%dT%H:%MZ)
- android archive: android/libraylib.a, $size bytes after llvm-strip --strip-debug
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

android_build_on_host() {
	# shellcheck source=android_env.sh
	. "$repository_root/tools/android_env.sh"
	fetch_source
	patch_default_shader_precision
	android_configure_and_build
	mkdir -p "$collection_directory/android"
	# The NDK compiles with -g even in Release; without the debug sections
	# the committed archive is a fraction of the size.
	"$ODIN_ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-debug \
		-o "$collection_directory/android/libraylib.a" "$android_build_directory/raylib/libraylib.a"
	write_android_build_record
	echo "built $collection_directory/android/libraylib.a"
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

android_build_in_container() {
	"$repository_root/tools/android_toolchain.sh"
	distrobox enter "$android_container_name" -- "$repository_root/tools/build_raylib.sh" --android --host
}

case "${1:-} ${2:-}" in
	"--host ") build_on_host ;;
	" ") build_in_container ;;
	"--android --host" | "--host --android") android_build_on_host ;;
	"--android ") android_build_in_container ;;
	*)
		echo "usage: $0 [--android] [--host]" >&2
		exit 2
		;;
esac
