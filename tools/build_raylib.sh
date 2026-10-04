#!/usr/bin/env bash
# Build raylib 6.0 from the upstream tag into the shared collection and
# rewrite that platform's build record in shared/raylib/README.md.
# Desktop: both GLFW backends (Wayland and X11, GLFW picks at run time)
# into shared/raylib/linux/libraylib.a, work item 0085. Android: arm64-v8a
# with OpenGL ES 3.0 into shared/raylib/android/libraylib.a, work item
# 0113. See doc/build.md (desktop) and doc/android.md (Android).
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

# The key branch of AndroidInputCallback (rcore_android.c) appends every
# key down to keyPressedQueue without checking MAX_KEY_PRESSED_QUEUE, and
# an IME committing a long word delivers every character's key down in
# one poll, so a text field on the system keyboard (work item 0133) could
# write past the queue. The append becomes bounded in the form the GLFW
# desktop platform uses (rcore_desktop_glfw.c): an if on the count below
# MAX_KEY_PRESSED_QUEUE around the store and the increment. Anything but
# one rewrite fails, so a raylib upgrade that moves the text is noticed.
patch_android_key_queue_bound() {
	local source_file="$source_directory/src/platforms/rcore_android.c"
	awk '
		/^[ \t]*CORE\.Input\.Keyboard\.keyPressedQueue\[CORE\.Input\.Keyboard\.keyPressedQueueCount\] = key;$/ && before_previous !~ /keyPressedQueueCount < MAX_KEY_PRESSED_QUEUE/ {
			store = $0
			if ((getline increment) <= 0 || increment !~ /^[ \t]*CORE\.Input\.Keyboard\.keyPressedQueueCount\+\+;$/) {
				exit 1
			}
			indentation = store
			sub(/[^ \t].*$/, "", indentation)
			print indentation "if (CORE.Input.Keyboard.keyPressedQueueCount < MAX_KEY_PRESSED_QUEUE)"
			print indentation "{"
			print "    " store
			print "    " increment
			print indentation "}"
			rewrites++
			before_previous = previous = ""
			next
		}
		{ print; before_previous = previous; previous = $0 }
		END { if (rewrites != 1) exit 1 }
	' "$source_file" > "$source_file.new" || {
		echo "rcore_android.c: expected one unbounded keyPressedQueue append" >&2
		rm -f "$source_file.new"
		exit 1
	}
	mv "$source_file.new" "$source_file"
}

# The gamepad key branch of AndroidInputCallback (rcore_android.c) in 6.0
# refuses a key event whose source carries the KEYBOARD bit beside the
# JOYSTICK or GAMEPAD bit, and Android stamps the KEYBOARD bit on every key
# event of a gamepad (the user's GameSir X2 reports source 0x01000511 on
# every button), so only the sticks' motion events reached the game (work
# item 0236). The block is rewritten into the form of upstream PR #5824
# (raysan5/raylib a005a044d, merged 2026-05-10, after the 6.0 tag): the
# source bits only select the branch, AndroidTranslateGamepadButton
# decides, and an unknown keycode (a phone's volume keys arrive with the
# GAMEPAD bit, the bug the 6.0 guard was added for) falls through to the
# keyboard handler. The block is matched whole and exactly once, so a
# raylib that has absorbed the fix fails here and the patch is dropped.
patch_android_gamepad_source_bits() {
	local source_file="$source_directory/src/platforms/rcore_android.c"
	local old_block new_block
	old_block=$(cat <<'EOF'
        // Handle gamepad button presses and releases
        // NOTE: Skip gamepad handling if this is a keyboard event, as some devices
        // report both AINPUT_SOURCE_KEYBOARD and AINPUT_SOURCE_GAMEPAD flags
        if ((FLAG_IS_SET(source, AINPUT_SOURCE_JOYSTICK) ||
             FLAG_IS_SET(source, AINPUT_SOURCE_GAMEPAD)) &&
            !FLAG_IS_SET(source, AINPUT_SOURCE_KEYBOARD))
        {
            // Assuming a single gamepad, "detected" on its input event
            CORE.Input.Gamepad.ready[0] = true;

            GamepadButton button = AndroidTranslateGamepadButton(keycode);

            if (button == GAMEPAD_BUTTON_UNKNOWN) return 1;

            if (AKeyEvent_getAction(event) == AKEY_EVENT_ACTION_DOWN)
            {
                CORE.Input.Gamepad.currentButtonState[0][button] = 1;
            }
            else CORE.Input.Gamepad.currentButtonState[0][button] = 0;  // Key up

            return 1; // Handled gamepad button
        }
EOF
)
	new_block=$(cat <<'EOF'
        // Handle gamepad button presses and releases. AOSP stamps the
        // KEYBOARD source bit on every key event from a gamepad, so
        // discriminate on the keycode rather than gating on source bits.
        if (FLAG_IS_SET(source, AINPUT_SOURCE_JOYSTICK) ||
            FLAG_IS_SET(source, AINPUT_SOURCE_GAMEPAD))
        {
            GamepadButton button = AndroidTranslateGamepadButton(keycode);

            if (button != GAMEPAD_BUTTON_UNKNOWN)
            {
                // Assuming a single gamepad, "detected" on its input event
                CORE.Input.Gamepad.ready[0] = true;

                if (AKeyEvent_getAction(event) == AKEY_EVENT_ACTION_DOWN)
                {
                    CORE.Input.Gamepad.currentButtonState[0][button] = 1;
                }
                else CORE.Input.Gamepad.currentButtonState[0][button] = 0;  // Key up

                return 1; // Handled gamepad button
            }
            // Unknown keycode: fall through to the keyboard handler below.
        }
EOF
)
	OLD_BLOCK="$old_block" NEW_BLOCK="$new_block" awk '
		BEGIN { RS = "^$"; old = ENVIRON["OLD_BLOCK"]; new = ENVIRON["NEW_BLOCK"] }
		{
			start = index($0, old)
			if (start == 0) exit 1
			rest = substr($0, start + length(old))
			if (index(rest, old) != 0) exit 1
			printf "%s%s%s", substr($0, 1, start - 1), new, rest
		}
	' "$source_file" > "$source_file.new" || {
		echo "rcore_android.c: expected the 6.0 gamepad key block of AndroidInputCallback once" >&2
		rm -f "$source_file.new"
		exit 1
	}
	mv "$source_file.new" "$source_file"
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
- android source patch: src/platforms/rcore_android.c, the key branch's keyPressedQueue append is bounded by MAX_KEY_PRESSED_QUEUE as on the desktop (work item 0133)
- android source patch: src/platforms/rcore_android.c, the gamepad key block of AndroidInputCallback routes by keycode instead of refusing events with the KEYBOARD source bit, as upstream PR #5824 (work item 0236)
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
	patch_android_key_queue_bound
	patch_android_gamepad_source_bits
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
