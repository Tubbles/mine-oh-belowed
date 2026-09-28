#!/usr/bin/env bash
# Smoke test a Windows build under Proton's Wine on this machine, without
# a display (work item 0102): prints the version, then starts the game so
# it loads its data and fails at the window, and shows the log it wrote
# beside the executable (work item 0103). A Wine abort (an unimplemented
# function) shows here before the build reaches the phone.
#   tools/wine_smoke_test.sh [path/to/mine-oh-belowed.exe]
# Default: the newest executable under tmp/artifact (gh run download).
# The prefix is tmp/wineprefix, made on the first run.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wine="$HOME/.steam/steam/steamapps/common/Proton 11.0/files/bin/wine"
executable="${1:-$(find "$repository_root/tmp/artifact" -name mine-oh-belowed.exe -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-)}"
if [ -z "$executable" ] || [ ! -f "$executable" ]; then
	echo "no executable: pass the path, or gh run download into tmp/artifact" >&2
	exit 2
fi
if [ ! -x "$wine" ]; then
	echo "no Proton wine at $wine" >&2
	exit 2
fi

export WINEPREFIX="$repository_root/tmp/wineprefix"
export WINEDEBUG=-all
export DISPLAY=
export WAYLAND_DISPLAY=

"$wine" "$executable" --version
# Without a display the window cannot open, which ends the start after
# the data loaded; a Wine abort ends it earlier and says so.
timeout 120 "$wine" "$executable" || echo "exit $? (1 with no display is the expected end)"
log="$(dirname "$executable")/log.txt"
if [ -f "$log" ]; then
	echo "--- $log"
	tail -n 20 "$log"
fi
