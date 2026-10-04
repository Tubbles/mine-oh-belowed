"""Write the OBJ machine models to data/models/ (work item 0204,
doc/build.md, Models). Runs inside Blender:

    tools/blender tools/make_models.py [model ...]

No model names means all of tools/models/machines. Each machine's
script gets its record (tools/models/records.py, work item 0207) and is
built in an empty scene and exported as <model>.obj and <model>.mtl; the same
script in the same Blender version writes the same bytes. A model in
COLLISIONS (work item 0230) also gets <model>.collision.sjson from its
script's collision(b) (tools/models/collision.py); every other model's
collision file is removed. The committed files are the product: the
build, the tests and CI never run Blender.
"""

import pathlib
import sys

TOOLS_DIRECTORY = pathlib.Path(__file__).resolve().parent
REPOSITORY_ROOT = TOOLS_DIRECTORY.parent
sys.path.insert(0, str(TOOLS_DIRECTORY))

from models import collision, kit, records  # noqa: E402
from models.machines import COLLISIONS, MACHINES  # noqa: E402


def requested_models(arguments):
    """The names after "--", all machines when there are none."""
    names = arguments[arguments.index("--") + 1:] if "--" in arguments else []
    unknown = [name for name in names if name not in MACHINES]
    if unknown:
        print(f"unknown model {', '.join(unknown)}; known: {', '.join(MACHINES)}", file=sys.stderr)
        sys.exit(1)
    return [name for name in MACHINES if not names or name in names]


def write_collision_file(name, machine, directory):
    """The model's collision volumes, or the removal of a stale file."""
    path = directory / f"{name}{collision.FILE_SUFFIX}"
    if name in COLLISIONS:
        b = collision.Collision(machine)
        COLLISIONS[name](b)
        collision.write(b, path)
        print(f"wrote data/models/{name}{collision.FILE_SUFFIX} ({b.count()} volumes)")
    elif path.exists():
        path.unlink()
        print(f"removed data/models/{name}{collision.FILE_SUFFIX}")


def main():
    directory = REPOSITORY_ROOT / "data" / "models"
    machines = records.load_machines(REPOSITORY_ROOT / "data" / "machines.sjson")
    for name in requested_models(sys.argv):
        kit.clear_scene()
        machine = records.machine_for_model(machines, name)
        MACHINES[name](machine)
        kit.export(name, directory)
        print(f"wrote data/models/{name}.obj")
        write_collision_file(name, machine, directory)


main()
