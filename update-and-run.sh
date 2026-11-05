#!/usr/bin/env bash
# The couch's way into the water tech demo (work item 0291): pulls main
# from origin, builds the release and runs it with --tech-demo (the title
# with the Tech demo screen open) unless arguments are given, which go to
# the game as they are (Steam LaunchOptions --tech-demo=teleport,8000,spring
# skips the title). It refuses a checkout that is not on main and a tree
# with changes under src/ or data/, since the pull would fail or the build
# would not be main's, and prints why. MINE_OH_BELOWED_GAMESCOPE is
# honoured as the play launcher does.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repository_root"

branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" != "main" ]; then
	echo "update-and-run.sh: the checkout is on $branch, not main; check out main first" >&2
	exit 1
fi
if [ -n "$(git status --porcelain -- src data)" ]; then
	echo "update-and-run.sh: src/ or data/ has uncommitted changes, commit or stash them first:" >&2
	git status --short -- src data >&2
	exit 1
fi
git pull --ff-only origin main
./build.sh release

if [ $# -eq 0 ]; then
	set -- --tech-demo
fi
if [ -n "${MINE_OH_BELOWED_GAMESCOPE:-}" ]; then
	if command -v gamescope >/dev/null; then
		# shellcheck disable=SC2086
		exec gamescope $MINE_OH_BELOWED_GAMESCOPE -- "$repository_root/build/mine-oh-belowed" "$@"
	fi
	echo "update-and-run.sh: MINE_OH_BELOWED_GAMESCOPE is set but gamescope is not on the path, running without it" >&2
fi
exec "$repository_root/build/mine-oh-belowed" "$@"
