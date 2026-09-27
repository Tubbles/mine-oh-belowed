#!/usr/bin/env bash
# Install the play build the Steam shortcut launches: a commit (HEAD, or
# the first argument), built in release mode, into its own directory under
# bin/play/builds/ with its own copy of data/, then pointed at by the
# bin/play/current link, which the launcher bin/mine-oh-belowed resolves
# at launch. The install never waits for the game: a running game keeps
# its build directory and the next launch takes the newest. The two newest
# builds stay (double buffering), older ones go unless a game still runs
# from them. The working tree is never read by the installed game, so
# agents editing src/ and data/ cannot break a couch session. Run it after
# every commit that lands on main.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
play_root="$repository_root/bin/play"
builds_directory="$play_root/builds"
launcher="$repository_root/bin/mine-oh-belowed"
ref="${1:-HEAD}"
commit="$(git -C "$repository_root" rev-parse --short "$ref")"
# Sorts by install time, so the newest is last.
build_name="$(date -u +%Y%m%dT%H%M%SZ)-$commit"
keep_count=2
staging="$(mktemp -d "${TMPDIR:-/tmp}/mine-oh-belowed-play.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

git -C "$repository_root" archive --format=tar "$ref" | tar -x -C "$staging"
# The archive has no .git, so the stamp gets the commit from here.
export MINE_OH_BELOWED_COMMIT="$commit"
"$staging/build.sh" release

built="$staging/build/mine-oh-belowed"
if [ ! -x "$built" ]; then
	built="$staging/bin/mine-oh-belowed"
fi

build_directory="$builds_directory/$build_name"
mkdir -p "$build_directory"
cp "$built" "$build_directory/mine-oh-belowed"
cp -r "$staging/data" "$build_directory/data"
printf '%s\n' "$commit" > "$build_directory/COMMIT"

# One rename switches the link, so a launch never finds it missing.
ln -sfn "builds/$build_name" "$play_root/current.new"
mv -Tf "$play_root/current.new" "$play_root/current"

# The flat layout of installs before double buffering, unless a game still
# runs from it.
if [ -e "$play_root/mine-oh-belowed" ] && ! pgrep -f "$play_root/mine-oh-belowed" >/dev/null; then
	rm -rf "$play_root/mine-oh-belowed" "$play_root/data" "$play_root/COMMIT"
fi

# Older builds go, except one a game runs from (its command line names the
# build directory).
find "$builds_directory" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$((keep_count + 1)) | while read -r old_build; do
	if pgrep -f "$old_build/" >/dev/null; then
		continue
	fi
	rm -rf "$old_build"
done

cat > "$launcher" <<'LAUNCHER'
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
exec "$build_directory/mine-oh-belowed" "$@"
LAUNCHER
chmod +x "$launcher"

echo "installed play build of $commit to $build_directory"
