#!/bin/bash
# A clip of consecutive frames from a running developer session paused
# where wanted (work item 0286, doc/commands.md, For the assistant), so
# the motion is judged and not one still.
#
#   tools/capture_clip.sh <name> [frames=60] [crop=140x150+580+160]
#
# Per frame: one tick, then a screenshot <name>_NN, waiting for its file
# to be whole (the game writes it once it drew its next frame). Then, in
# the screenshot directory, <name>_strip.png (every third frame cropped
# to crop, ten a row) and <name>.gif (every frame at 640x360, two
# hundredths of a second each, near the tick rate). Prints both paths.
# MOC names the command client (default tools/moc, so a session's
# wrapper can stand in), SCREENSHOTS the directory the game writes its
# screenshots to.
set -eu

name=${1:?usage: tools/capture_clip.sh <name> [frames] [crop]}
frames=${2:-60}
crop=${3:-140x150+580+160}
moc=${MOC:-"$(dirname "$0")/moc"}
screenshots=${SCREENSHOTS:-"${XDG_STATE_HOME:-$HOME/.local/state}/mine-oh-belowed/screenshots"}
width=${#frames}
if [ "$width" -lt 2 ]; then
	width=2
fi

# Waits up to ten seconds for a file to appear and stop growing (the
# game writes it in place), polling every 0.05 s.
wait_for_file() {
	last_size=-1
	for _ in $(seq 200); do
		if [ -f "$1" ]; then
			size=$(stat -c %s "$1")
			if [ "$size" -gt 0 ] && [ "$size" -eq "$last_size" ]; then
				return 0
			fi
			last_size=$size
		fi
		sleep 0.05
	done
	echo "capture_clip: $1 did not appear" >&2
	return 1
}

all_frames=()
strip_frames=()
for index in $(seq 0 $((frames - 1))); do
	frame_name=$(printf '%s_%0*d' "$name" "$width" "$index")
	path="$screenshots/$frame_name.png"
	rm -f "$path"
	"$moc" tick 1 > /dev/null
	"$moc" screenshot "$frame_name" > /dev/null
	wait_for_file "$path"
	all_frames+=("$path")
	if [ $((index % 3)) -eq 0 ]; then
		strip_frames+=("$path[$crop]")
	fi
done

strip="$screenshots/${name}_strip.png"
clip="$screenshots/$name.gif"
magick montage "${strip_frames[@]}" -tile 10x -geometry +2+2 "$strip"
magick -delay 2 -loop 0 "${all_frames[@]}" -resize 640x360 "$clip"
echo "$strip"
echo "$clip"
