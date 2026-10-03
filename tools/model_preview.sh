#!/usr/bin/env bash
# Renders the machines' models from the workbench's four cameras at rest
# and at three phases (work item 0207, doc/build.md, The workbench): 16
# PNG files per machine in $MODEL_PREVIEW_DIRECTORY, tmp/model_preview by
# default. Always under a virtual display of its own (xvfb-run picks a
# free one and stops it), also when a display is set, so no window opens
# on the couch.
#
# Usage: tools/model_preview.sh <machine>[,<machine>] [machine ...]
set -euo pipefail
if [ "$#" -lt 1 ]; then
	echo "usage: $0 <machine>[,<machine>] [machine ...]" >&2
	exit 2
fi
cd "$(dirname "${BASH_SOURCE[0]}")/.."
machines="$(IFS=,; printf '%s' "$*")"
directory="${MODEL_PREVIEW_DIRECTORY:-tmp/model_preview}"
./build.sh debug
exec xvfb-run -a -s "-screen 0 1280x720x24" build/mine-oh-belowed --model-preview="$machines" --model-preview-directory="$directory"
