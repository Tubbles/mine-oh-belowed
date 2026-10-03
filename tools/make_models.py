"""Write the OBJ machine models to data/models/ (work item 0204,
doc/build.md, Models). Runs inside Blender:

    tools/blender tools/make_models.py [model ...]

No model names means all of tools/models/machines. Each machine is built
in an empty scene and exported as <model>.obj and <model>.mtl; the same
script in the same Blender version writes the same bytes. The committed
files are the product: the build, the tests and CI never run Blender.
"""

import pathlib
import sys

TOOLS_DIRECTORY = pathlib.Path(__file__).resolve().parent
REPOSITORY_ROOT = TOOLS_DIRECTORY.parent
sys.path.insert(0, str(TOOLS_DIRECTORY))

from models import kit  # noqa: E402
from models.machines import MACHINES  # noqa: E402


def requested_models(arguments):
    """The names after "--", all machines when there are none."""
    names = arguments[arguments.index("--") + 1:] if "--" in arguments else []
    unknown = [name for name in names if name not in MACHINES]
    if unknown:
        print(f"unknown model {', '.join(unknown)}; known: {', '.join(MACHINES)}", file=sys.stderr)
        sys.exit(1)
    return [name for name in MACHINES if not names or name in names]


def main():
    directory = REPOSITORY_ROOT / "data" / "models"
    for name in requested_models(sys.argv):
        kit.clear_scene()
        MACHINES[name]()
        kit.export(name, directory)
        print(f"wrote data/models/{name}.obj")


main()
