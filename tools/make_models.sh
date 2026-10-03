#!/usr/bin/env bash
# Rebuilds the OBJ machine models in Blender, then checks them in the game
# (work item 0207, doc/build.md, The workbench). It exits as the check
# does, so a committed model passes.
#
# Usage: tools/make_models.sh [model ...]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
tools/blender tools/make_models.py "$@"
exec ./build.sh model-check
