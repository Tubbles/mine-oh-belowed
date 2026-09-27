#!/usr/bin/env bash
# Install the play build the Steam shortcut launches: the latest commit,
# built in release mode, with its own copy of data/, under bin/play/, plus
# a launcher at bin/mine-oh-belowed. The working tree is never read by the
# installed game, so agents editing src/ and data/ cannot break a couch
# session. Run it after every landed commit that should reach the couch.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
play_directory="$repository_root/bin/play"
launcher="$repository_root/bin/mine-oh-belowed"
commit="$(git -C "$repository_root" rev-parse --short HEAD)"
staging="$(mktemp -d "${TMPDIR:-/tmp}/mine-oh-belowed-play.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

git -C "$repository_root" archive --format=tar HEAD | tar -x -C "$staging"
"$staging/build.sh" release

built="$staging/build/mine-oh-belowed"
if [ ! -x "$built" ]; then
	built="$staging/bin/mine-oh-belowed"
fi

rm -rf "$play_directory"
mkdir -p "$play_directory"
cp "$built" "$play_directory/mine-oh-belowed"
cp -r "$staging/data" "$play_directory/data"
printf '%s\n' "$commit" > "$play_directory/COMMIT"

cat > "$launcher" <<'LAUNCHER'
#!/usr/bin/env bash
# Launcher the Steam shortcut points at. Runs the installed play build with
# its own data directory, independent of the working tree.
play_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/play" && pwd)"
cd "$play_directory"
export MINE_OH_BELOWED_DATA="$play_directory/data"
exec "$play_directory/mine-oh-belowed" "$@"
LAUNCHER
chmod +x "$launcher"

echo "installed play build of $commit to $play_directory"
