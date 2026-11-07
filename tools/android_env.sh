# Android SDK and NDK locations for Odin's android subtarget and
# `odin bundle android`. Work item 0113, see doc/android.md
# (Toolchain). Source it, do not run it:
#   . tools/android_env.sh
# The NDK and build-tools float (0315): the newest installed under the
# SDK, on CI the runner's ANDROID_HOME (/usr/local/lib/android/sdk), on
# the couch the newest tools/android_toolchain.sh installed under
# ~/opt/android/sdk. odin bundle android picks the newest build-tools and
# platform itself.

ODIN_ANDROID_SDK="${ODIN_ANDROID_SDK:-${ANDROID_HOME:-$HOME/opt/android/sdk}}"
# || true: the file is sourced under set -euo pipefail, and the installer
# sources it before anything is installed.
ANDROID_NDK_VERSION="$(ls -1 "$ODIN_ANDROID_SDK/ndk" 2> /dev/null | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -n 1 || true)"
ANDROID_BUILD_TOOLS_VERSION="$(ls -1 "$ODIN_ANDROID_SDK/build-tools" 2> /dev/null | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -n 1 || true)"
# The manifest's targetSdkVersion, pinned: a product target rather than a
# tool. It opts the app into that release's behaviour changes, which the
# phone was tested against.
ANDROID_TARGET_SDK_VERSION=34
# The minimum level (Android 10): the -minimum-os-version passed to odin
# and the manifest's minSdkVersion. From Odin dev-2026-11 the runtime uses
# ELF thread local storage, which Android loads from 29. raylib's archive
# is built for 28, which links into a higher level.
ANDROID_API_LEVEL=29
ODIN_ANDROID_NDK="${ODIN_ANDROID_NDK:-$ODIN_ANDROID_SDK/ndk/$ANDROID_NDK_VERSION}"
PATH="$ODIN_ANDROID_SDK/build-tools/$ANDROID_BUILD_TOOLS_VERSION:$ODIN_ANDROID_SDK/platform-tools:$PATH"
export ANDROID_NDK_VERSION ANDROID_BUILD_TOOLS_VERSION ANDROID_TARGET_SDK_VERSION ANDROID_API_LEVEL ODIN_ANDROID_SDK ODIN_ANDROID_NDK PATH
