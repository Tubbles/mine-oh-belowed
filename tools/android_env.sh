# Android SDK and NDK locations for Odin's android subtarget and
# `odin bundle android`. Work item 0113, see doc/android.md
# (Toolchain). Source it, do not run it:
#   . tools/android_env.sh
# The versions match the GitHub ubuntu-24.04 runner, whose ANDROID_HOME
# (/usr/local/lib/android/sdk) holds the same NDK under ndk/, so the file
# serves there too. On the couch tools/android_toolchain.sh installs them
# under ~/opt/android/sdk.

ANDROID_NDK_VERSION=27.3.13750724
ANDROID_BUILD_TOOLS_VERSION=34.0.0
ANDROID_PLATFORM_VERSION=34
# The -minimum-os-version passed to odin (Android 9). raylib's archive is
# built for the same level (ANDROID_PLATFORM=android-28).
ANDROID_API_LEVEL=28
ODIN_ANDROID_SDK="${ODIN_ANDROID_SDK:-${ANDROID_HOME:-$HOME/opt/android/sdk}}"
ODIN_ANDROID_NDK="${ODIN_ANDROID_NDK:-$ODIN_ANDROID_SDK/ndk/$ANDROID_NDK_VERSION}"
PATH="$ODIN_ANDROID_SDK/build-tools/$ANDROID_BUILD_TOOLS_VERSION:$ODIN_ANDROID_SDK/platform-tools:$PATH"
export ANDROID_NDK_VERSION ANDROID_BUILD_TOOLS_VERSION ANDROID_PLATFORM_VERSION ANDROID_API_LEVEL ODIN_ANDROID_SDK ODIN_ANDROID_NDK PATH
