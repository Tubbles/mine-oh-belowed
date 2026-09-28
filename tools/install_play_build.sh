#!/usr/bin/env bash
# Install the play build the Steam shortcut launches: a commit (HEAD, or
# the commit argument), built in release mode, into its own directory
# under bin/play/builds/ with its own copy of data/, then pointed at by the
# bin/play/current link, which the launcher bin/mine-oh-belowed resolves
# at launch. The install never waits for the game: a running game keeps
# its build directory and the next launch takes the newest. The two newest
# builds stay (double buffering), older ones go unless a game still runs
# from them. The working tree is never read by the installed game, so
# agents editing src/ and data/ cannot break a couch session. Run it after
# every commit that lands on main.
#
# --target user@host:path (work item 0076, the Steam Deck) builds here the
# same way and installs over ssh and rsync instead: path on the host takes
# the place of bin/ (play/builds/, play/current and the launcher
# mine-oh-belowed), and nothing is installed locally.
set -euo pipefail

usage() {
	cat <<'USAGE'
usage: tools/install_play_build.sh [--target user@host:path] [commit]

Builds the commit (default HEAD) in release mode from a git archive and
installs it as the play build under bin/, or with --target under path on
the host over ssh and rsync (path absolute, or relative to the remote
home; it takes the place of bin/, so the launcher is path/mine-oh-belowed).
USAGE
}

ref=HEAD
target=""
while [ $# -gt 0 ]; do
	case "$1" in
		-h | --help)
			usage
			exit 0
			;;
		--target)
			[ $# -ge 2 ] || { usage >&2; exit 2; }
			target="$2"
			shift 2
			;;
		--target=*)
			target="${1#--target=}"
			shift
			;;
		-*)
			usage >&2
			exit 2
			;;
		*)
			ref="$1"
			shift
			;;
	esac
done

target_host=""
target_path=""
if [ -n "$target" ]; then
	target_host="${target%%:*}"
	target_path="${target#*:}"
	# A leading ~/ would reach the remote shell quoted; relative paths are
	# relative to the remote home anyway.
	target_path="${target_path#\~/}"
	if [ "$target_host" = "$target" ] || [ -z "$target_host" ] || [ -z "$target_path" ]; then
		echo "install_play_build.sh: --target must be user@host:path, got '$target'" >&2
		exit 2
	fi
fi

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
play_root="$repository_root/bin/play"
builds_directory="$play_root/builds"
launcher="$repository_root/bin/mine-oh-belowed"
commit="$(git -C "$repository_root" rev-parse --short "$ref")"
# Sorts by install time, so the newest is last.
build_name="$(date -u +%Y%m%dT%H%M%SZ)-$commit"
keep_count=2
staging="$(mktemp -d "${TMPDIR:-/tmp}/mine-oh-belowed-play.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

# One rename switches the link, so a launch never finds it missing.
# Arguments: the play directory, the build's name.
switch_current_build() {
	ln -sfn "builds/$2" "$1/current.new"
	mv -Tf "$1/current.new" "$1/current"
}

# Older builds go, except one a game runs from (its command line names the
# build directory). Arguments: the play directory, the builds to keep.
remove_old_builds() {
	find "$1/builds" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$(($2 + 1)) | while read -r old_build; do
		if pgrep -f "$old_build/" >/dev/null; then
			continue
		fi
		rm -rf "$old_build"
	done
}

# The launcher, into the file given.
write_launcher() {
	cat > "$1" <<'LAUNCHER'
#!/usr/bin/env bash
# Launcher the Steam shortcut points at. Resolves bin/play/current at
# launch and runs that build with its own data directory, independent of
# the working tree. An install while the game runs only moves the link;
# the running game keeps its build directory.
play_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/play" && pwd)"
build_directory="$(readlink -f "$play_root/current")"
cd "$build_directory"
export MINE_OH_BELOWED_DATA="$build_directory/data"
# Experiment (couch test 1, 2026-09-27): in Game Mode Steam keeps Steam
# Input on for the Steam Controller whatever the per game setting says,
# hands the game a virtual pad and tells SDL to ignore the real one. Let
# SDL open the controller itself and skip the virtual pad. The game's log
# says which device it got.
unset SDL_GAMECONTROLLER_IGNORE_DEVICES
export SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=0
# Work item 0085: the game opens a native Wayland window when the session
# (gamescope included) offers one. MINE_OH_BELOWED_X11=1 makes GLFW take
# X11 (XWayland under a Wayland desktop), the way back if Wayland
# misbehaves. Unsetting WAYLAND_DISPLAY alone is not enough: GLFW then
# still tries Wayland first, whose client library falls back to the
# wayland-0 socket; with XDG_SESSION_TYPE=x11 and DISPLAY set GLFW asks
# for X11 directly (glfw/src/platform.c, _glfwSelectPlatform).
if [ "${MINE_OH_BELOWED_X11:-}" = 1 ]; then
	unset WAYLAND_DISPLAY
	export XDG_SESSION_TYPE=x11
fi
# Work item 0084: MINE_OH_BELOWED_GAMESCOPE holds gamescope's own arguments
# (for example "-f -W 2880 -H 1920") and runs the game inside gamescope,
# which presents it at the panel's full size on a scaled Wayland desktop.
# Unquoted on purpose, so the arguments split into words.
if [ -n "${MINE_OH_BELOWED_GAMESCOPE:-}" ]; then
	if command -v gamescope >/dev/null; then
		# shellcheck disable=SC2086
		exec gamescope $MINE_OH_BELOWED_GAMESCOPE -- "$build_directory/mine-oh-belowed" "$@"
	fi
	echo "mine-oh-belowed: MINE_OH_BELOWED_GAMESCOPE is set but gamescope is not on the path, running without it" >&2
fi
exec "$build_directory/mine-oh-belowed" "$@"
LAUNCHER
	chmod +x "$1"
}

# The build directory with the binary, data/ and COMMIT. Arguments: the
# directory to fill.
fill_build_directory() {
	mkdir -p "$1"
	cp "$built" "$1/mine-oh-belowed"
	cp -r "$staging/data" "$1/data"
	printf '%s\n' "$commit" > "$1/COMMIT"
}

# The same install on the host: the build directory and the launcher go
# over with rsync, then the link switches and old builds go on the host,
# through the same procedures sent to a remote bash.
install_on_target() {
	local staged_build="$staging/install/$build_name"
	local remote_play="$target_path/play"
	fill_build_directory "$staged_build"
	write_launcher "$staging/install/mine-oh-belowed"
	ssh "$target_host" mkdir -p "$(printf '%q' "$remote_play/builds")"
	rsync -a "$staged_build/" "$target_host:$remote_play/builds/$build_name/"
	rsync -a "$staging/install/mine-oh-belowed" "$target_host:$target_path/mine-oh-belowed"
	{
		declare -f switch_current_build remove_old_builds
		printf 'switch_current_build %q %q\n' "$remote_play" "$build_name"
		printf 'remove_old_builds %q %q\n' "$remote_play" "$keep_count"
	} | ssh "$target_host" bash -s
	echo "installed play build of $commit to $target_host:$remote_play/builds/$build_name"
}

git -C "$repository_root" archive --format=tar "$ref" | tar -x -C "$staging"
# The archive has no .git, so the stamp gets the commit from here.
export MINE_OH_BELOWED_COMMIT="$commit"
"$staging/build.sh" release

built="$staging/build/mine-oh-belowed"
if [ ! -x "$built" ]; then
	built="$staging/bin/mine-oh-belowed"
fi

if [ -n "$target" ]; then
	install_on_target
	exit 0
fi

build_directory="$builds_directory/$build_name"
fill_build_directory "$build_directory"
switch_current_build "$play_root" "$build_name"

# The flat layout of installs before double buffering, unless a game still
# runs from it.
if [ -e "$play_root/mine-oh-belowed" ] && ! pgrep -f "$play_root/mine-oh-belowed" >/dev/null; then
	rm -rf "$play_root/mine-oh-belowed" "$play_root/data" "$play_root/COMMIT"
fi

remove_old_builds "$play_root" "$keep_count"
write_launcher "$launcher"

echo "installed play build of $commit to $build_directory"
