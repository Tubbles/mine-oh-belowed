#!/usr/bin/env bash
# Install the Android SDK pieces Odin's android subtarget and
# `odin bundle android` need: the command line tools, platform-tools,
# build-tools, one platform and the NDK, under
# ${ODIN_ANDROID_SDK:-$HOME/opt/android/sdk}. The versions are the GitHub
# ubuntu-24.04 runner's (tools/android_env.sh). Re-running skips what is
# installed. Work item 0113, see doc/android.md (Toolchain).
#   tools/android_toolchain.sh          install inside the distrobox
#                                       mine-oh-belowed-android (Fedora 44
#                                       with a headless JDK), created on
#                                       first use
#   tools/android_toolchain.sh --host   install on this machine, which
#                                       needs Java 17 or newer, curl and
#                                       unzip
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ODIN_ANDROID_SDK="${ODIN_ANDROID_SDK:-$HOME/opt/android/sdk}"
# shellcheck source=android_env.sh
. "$repository_root/tools/android_env.sh"

# From https://developer.android.com/studio#command-line-tools-only
# (read 2026-09-29).
command_line_tools_zip="commandlinetools-linux-15859902_latest.zip"
command_line_tools_sha256="4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"
command_line_tools_url="https://dl.google.com/android/repository/$command_line_tools_zip"
download_directory="$repository_root/tmp/android-downloads"
sdkmanager="$ODIN_ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
container_name="mine-oh-belowed-android"
container_image="registry.fedoraproject.org/fedora-toolbox:44"
# Fedora 44 has no java-21 package; 25 is its current long term JDK.
container_packages="java-25-openjdk-headless cmake gcc gcc-c++ make git unzip"

install_command_line_tools() {
	if [[ -x "$sdkmanager" ]]; then
		return
	fi
	mkdir -p "$download_directory"
	local zip="$download_directory/$command_line_tools_zip"
	if [[ ! -f "$zip" ]]; then
		curl --fail --location --output "$zip.part" "$command_line_tools_url"
		mv "$zip.part" "$zip"
	fi
	echo "$command_line_tools_sha256  $zip" | sha256sum --check
	local unpack_directory="$download_directory/cmdline-tools-unpacked"
	rm -rf "$unpack_directory"
	unzip -q "$zip" -d "$unpack_directory"
	mkdir -p "$ODIN_ANDROID_SDK/cmdline-tools"
	rm -rf "$ODIN_ANDROID_SDK/cmdline-tools/latest"
	mv "$unpack_directory/cmdline-tools" "$ODIN_ANDROID_SDK/cmdline-tools/latest"
	rm -rf "$unpack_directory"
}

# `yes` ends with SIGPIPE once sdkmanager stops reading, which pipefail
# would report as a failure.
accept_licenses() {
	{ yes || true; } | "$sdkmanager" --sdk_root="$ODIN_ANDROID_SDK" --licenses > /dev/null
}

install_packages() {
	local package_directories=(
		"platform-tools"
		"build-tools/$ANDROID_BUILD_TOOLS_VERSION"
		"platforms/android-$ANDROID_PLATFORM_VERSION"
		"ndk/$ANDROID_NDK_VERSION"
	)
	local missing=()
	local directory
	for directory in "${package_directories[@]}"; do
		if [[ ! -d "$ODIN_ANDROID_SDK/$directory" ]]; then
			missing+=("${directory/\//;}")
		fi
	done
	if [[ ${#missing[@]} -eq 0 ]]; then
		echo "all packages installed under $ODIN_ANDROID_SDK"
		return
	fi
	accept_licenses
	"$sdkmanager" --sdk_root="$ODIN_ANDROID_SDK" "${missing[@]}"
}

install_on_host() {
	install_command_line_tools
	install_packages
	echo "Android SDK ready under $ODIN_ANDROID_SDK"
}

# The home directory is shared with the container, so the same script runs
# inside it with --host and the SDK lands under ~/opt either way.
ensure_container() {
	if ! distrobox list --no-color | grep -q " $container_name "; then
		distrobox create --yes --name "$container_name" --image "$container_image" \
			--additional-packages "$container_packages"
	fi
}

case "${1:-}" in
	--host) install_on_host ;;
	"")
		ensure_container
		distrobox enter "$container_name" -- "$repository_root/tools/android_toolchain.sh" --host
		;;
	*)
		echo "usage: $0 [--host]" >&2
		exit 2
		;;
esac
