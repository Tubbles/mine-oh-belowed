#!/usr/bin/env bash
# The latest Odin release for a CI job (work item 0315, doc/build.md, CI):
# the release's odin-<platform>-<tag> archive, checked against the
# SHA-256 digest GitHub records for the asset (the release publishes no
# checksum file), unpacked under RUNNER_TEMP, and ODIN=<its odin> added
# to GITHUB_ENV. Needs gh with GH_TOKEN, curl, sha256sum, and 7z or tar.
#   tools/ci_download_odin.sh windows-amd64
#   tools/ci_download_odin.sh linux-amd64
set -euo pipefail

platform="$1"
downloads="$RUNNER_TEMP"
if command -v cygpath > /dev/null 2>&1; then
	downloads="$(cygpath -u "$RUNNER_TEMP")"
fi
assets="$(gh api repos/odin-lang/Odin/releases/latest --jq '.tag_name as $tag | .assets[] | [$tag, .name, .digest, .browser_download_url] | @tsv')"
matches="$(awk -F '\t' -v prefix="odin-$platform-" 'index($2, prefix) == 1' <<< "$assets")"
if [ -z "$matches" ] || [ "$(wc -l <<< "$matches")" -ne 1 ]; then
	echo "expected one odin-$platform- asset in the latest Odin release, which has:" >&2
	cut -f 1,2 <<< "$assets" >&2
	exit 1
fi
IFS=$'\t' read -r tag name digest url <<< "$matches"
if [ "${digest#sha256:}" = "$digest" ]; then
	echo "$name has no SHA-256 digest on GitHub: '$digest'" >&2
	exit 1
fi
archive="$downloads/$name"
curl --fail --location --silent --show-error --output "$archive" "$url"
echo "${digest#sha256:}  $archive" | sha256sum --check -
mkdir -p "$downloads/odin"
case "$name" in
	*.zip) 7z x -o"$downloads/odin" "$archive" > /dev/null ;;
	*.tar.gz) tar -xzf "$archive" -C "$downloads/odin" ;;
	*) echo "unknown archive type: $name" >&2; exit 1 ;;
esac
executable_name=odin
if [[ "$platform" == windows-* ]]; then
	executable_name=odin.exe
fi
odin_executable="$(find "$downloads/odin" -name "$executable_name" -type f -print -quit)"
if [ -z "$odin_executable" ]; then
	echo "$executable_name not found in $name" >&2
	exit 1
fi
echo "ODIN=$odin_executable" >> "$GITHUB_ENV"
echo "Odin $tag ($name)"
"$odin_executable" version
