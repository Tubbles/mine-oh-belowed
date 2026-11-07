#!/usr/bin/env bash
# Install the Android SDK pieces Odin's android subtarget and
# `odin bundle android` need: the command line tools, platform-tools, the
# newest stable build-tools and NDK sdkmanager lists (they float, 0315),
# and the platform of the target SDK tools/android_env.sh pins, under
# ${ODIN_ANDROID_SDK:-$HOME/opt/android/sdk}. Re-running skips what is
# installed and adds a newer build-tools or NDK. Work item 0113, see
# doc/android.md (Toolchain).
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
# (read 2026-09-29). Pinned with its SHA-256: it only bootstraps
# sdkmanager, which installs the floating packages (0315).
command_line_tools_zip="commandlinetools-linux-15859902_latest.zip"
command_line_tools_sha256="4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"
command_line_tools_url="https://dl.google.com/android/repository/$command_line_tools_zip"
download_directory="$repository_root/tmp/android-downloads"
sdkmanager="$ODIN_ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
container_name="mine-oh-belowed-android"
# Pinned: distrobox creates the container once and keeps it, so a newer
# Fedora comes by raising the release here, removing the container and
# running this script again (0315).
container_image="registry.fedoraproject.org/fedora-toolbox:44"
# Fedora names its JDK packages by version, so the JDK follows the image.
# Fedora 44 has no java-21 package, and 25 is its current long term JDK.
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

# The newest stable version of an SDK package in sdkmanager's list, such
# as ndk or build-tools (0315). Both the package name and the version
# column must hold a bare version: a build-tools release candidate shows
# its rc in the name (build-tools;37.0.0-rc1), an NDK one only in the
# version column (ndk;30.0.16138531 | 30.0.16138531 rc3).
newest_package_version() {
	"$sdkmanager" --sdk_root="$ODIN_ANDROID_SDK" --list \
		| sed -n -E "s/^ *$1;([0-9]+(\.[0-9]+)*) +\| +[0-9]+(\.[0-9]+)* +\|.*/\1/p" | sort -V | tail -n 1
}

install_packages() {
	local build_tools_version ndk_version
	build_tools_version="$(newest_package_version build-tools)"
	ndk_version="$(newest_package_version ndk)"
	if [[ -z "$build_tools_version" || -z "$ndk_version" ]]; then
		echo "sdkmanager lists no stable build-tools or ndk version (build-tools '$build_tools_version', ndk '$ndk_version')" >&2
		exit 1
	fi
	local package_directories=(
		"platform-tools"
		"build-tools/$build_tools_version"
		"platforms/android-$ANDROID_TARGET_SDK_VERSION"
		"ndk/$ndk_version"
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
