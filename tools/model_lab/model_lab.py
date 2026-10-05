#!/usr/bin/env python3
"""Builds the sealed modelling lab of one or more machine models and
hands a lab's models to the game (work item 0214, doc/build.md, The
workbench).

    python3 tools/model_lab/model_lab.py build <model>[,<model>...] <reference directory> [--rework] [--lab <directory>] [--brief <file>] [--replace]
    python3 tools/model_lab/model_lab.py preview <lab directory> [<model> ...]

build writes tmp/model_lab/<first model>/ of the main checkout (or the
--lab directory, which must be in a tmp directory under the main
checkout: the Flatpak Blender does not see /tmp): the filled brief, the
lab's records, copies of the kit and the lab's check and renderer, the
reference images, the reference models' renders (work item 0275: the
game's accepted models from doc/art/booklet/, the yardstick of the look
and the density, never the model the lab remakes) and a stub script per
model (with --rework, the repository's scripts and model files
instead). It builds in a staging
directory beside the lab and renames it into place, and replaces an
existing lab only with --replace.

preview, run in the item's worktree, copies the lab's model files into
data/models/, prints the record difference, and runs the game's model
check and preview of the models.
"""

import argparse
import ast
import difflib
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
LAB_TOOLS = REPOSITORY_ROOT / "tools" / "model_lab"
sys.path.insert(0, str(REPOSITORY_ROOT / "tools"))

import sjson  # noqa: E402
from models import records  # noqa: E402

import check  # noqa: E402

COPIED_TOOLS = (
    "tools/blender",
    "tools/sjson.py",
    "tools/make_models.py",
    "tools/models/__init__.py",
    "tools/models/kit.py",
    "tools/models/palette.py",
    "tools/models/records.py",
    "tools/models/collision.py",
)
LAB_FILES = ("check.py", "render.py")
MODEL_ROUND_STRIPPED_KEYS = ("open_cells", "fixtures", "lights", "interior_light_share")
REWORK_ROUND_STRIPPED_KEYS = ("lights", "interior_light_share")
IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp")
MODEL_NAME = re.compile(r"[a-z0-9_]+")
STUB_BODY_MATERIAL = "steel"
STUB_PART_MATERIAL = "galvanised"
EXTERIOR_VIEWS = ("front_right", "front_left", "back_left", "top", "close")
MACHINES_PATH = REPOSITORY_ROOT / "data" / "machines.sjson"
BOOKLET = REPOSITORY_ROOT / "doc" / "art" / "booklet"
REFERENCE_MODELS_DIRECTORY = "reference_models"
# The reference models (DESIGN.md, Art direction, work item 0275) in the
# order of the game's MODEL_REFERENCE_MACHINES, each with its renders in
# BOOKLET: (file, caption). The pod's are its lab previews, made by the
# same renderer as the modeller's own; the furnace has the game's render.
REFERENCE_MODELS = (
    ("stone_furnace", (("furnace_model_front_left.jpg", "the game's render from the hero angle, lit by the game"),)),
    (
        "pod",
        (
            ("pod_model_round3_exterior.jpg", "the lab's preview from outside: the riveted cone, the shutter, the antenna"),
            ("pod_model_round3_chair.jpg", "the lab's preview of the cabin from the chair: the desk, keypads, levers, cabinets, the oxygen manifold"),
            ("pod_model_round3_lamps.jpg", "the lab's preview looking up: the lamp strip on its brackets, the portholes, the desk lamp"),
        ),
    ),
)
# The renders that show a reference's inside, with its fixtures: a lab
# remaking one of its fixtures gets the other renders only.
REFERENCE_INSIDE_IMAGES = ("pod_model_round3_chair.jpg", "pod_model_round3_lamps.jpg")


def parse_models(argument):
    """The comma separated model names, each a machine id's spelling."""
    models = [name for name in argument.split(",") if name]
    if not models:
        raise SystemExit("no model named")
    for name in models:
        if not MODEL_NAME.fullmatch(name):
            raise SystemExit(f"bad model name {name!r}: lower case letters, digits and _ only")
    repeated = sorted({name for name in models if models.count(name) > 1})
    if repeated:
        raise SystemExit(f"model named twice: {', '.join(repeated)}")
    return models


def record_blocks(machines_text, key, value):
    """Every record block holding the line <key> = "<value>", file order,
    from its tab { line to its tab } line with the final newline."""
    blocks, current = [], None
    wanted = f'\t\t{key} = "{value}"'
    for line in machines_text.splitlines(keepends=True):
        if line.rstrip("\n") == "\t{":
            current = [line]
        elif current is not None:
            current.append(line)
            if line.rstrip("\n") == "\t}":
                if any(entry.rstrip("\n") == wanted for entry in current):
                    blocks.append("".join(current))
                current = None
    return blocks


def entry_key(line, keys):
    """The key of keys this record line sets at two tabs, or None."""
    if not line.startswith("\t\t") or line.startswith("\t\t\t"):
        return None
    return next((key for key in keys if line[2:].startswith(f"{key} = ")), None)


def stripped_block(block, keys):
    """The block without each entry of keys (a line, or an array or an
    object to its closing line) and the comment lines directly above."""
    lines = block.splitlines(keepends=True)
    kept, index = [], 0
    while index < len(lines):
        line = lines[index]
        if entry_key(line, keys) is None:
            kept.append(line)
            index += 1
            continue
        while kept and kept[-1].startswith("\t\t//"):
            kept.pop()
        closing = {"[": "\t\t]", "{": "\t\t}"}.get(line.rstrip()[-1:])
        if closing is not None:
            while lines[index].rstrip() != closing:
                index += 1
        index += 1
    return "".join(kept)


def parsed_records(blocks):
    """The blocks read as record dictionaries."""
    return sjson.loads("machines = [\n" + "".join(blocks) + "]")["machines"]


def fixture_machine_ids(blocks):
    """The machine of every fixtures entry, first appearance, no repeats."""
    identifiers = []
    for record in parsed_records(blocks):
        for fixture in record.get("fixtures", []):
            if fixture["machine"] not in identifiers:
                identifiers.append(fixture["machine"])
    return identifiers


def records_header(stripped_keys):
    return [
        "// The machine records of this lab. footprint: width (x), depth (z) and",
        "// height (y) in cells of 0.5 m. motion: how the moving part moves, its",
        "// pivot (and an iris's hinge) in cells from the footprint's minimum",
        "// corner: x the width, y up, z the depth.",
        f"// Removed for this lab: {', '.join(stripped_keys)}.",
    ]


def model_blocks(machines_text, model):
    blocks = record_blocks(machines_text, "model", model)
    if not blocks:
        raise SystemExit(f"no record in data/machines.sjson names the model {model}")
    return blocks


def fixture_blocks(machines_text, blocks):
    """The unstripped records of the blocks' fixtures not among them."""
    included = {record["id"] for record in parsed_records(blocks)}
    added = []
    for identifier in fixture_machine_ids(blocks):
        if identifier in included:
            continue
        found = record_blocks(machines_text, "id", identifier)
        if not found:
            raise SystemExit(f"no record in data/machines.sjson has the fixture's id {identifier}")
        added += found
        included.add(identifier)
    return added


def without_comments(block):
    """The block without its // comment lines."""
    return "".join(line for line in block.splitlines(keepends=True) if not line.lstrip().startswith("//"))


def lab_records_text(machines_text, models, stripped_keys, with_fixtures):
    """The lab's data/machines.sjson. A first round (without fixtures)
    drops the records' comment lines too, which describe the old model
    and name other items; a rework round keeps them."""
    blocks = [stripped_block(block, stripped_keys) for model in models for block in model_blocks(machines_text, model)]
    if not with_fixtures:
        blocks = [without_comments(block) for block in blocks]
    if with_fixtures:
        blocks += fixture_blocks(machines_text, blocks)
    return "\n".join(records_header(stripped_keys)) + "\nmachines = [\n" + "".join(blocks) + "]\n"


def helper_modules(script_text):
    """The modules a machine script imports from its own package."""
    names = set()
    for node in ast.walk(ast.parse(script_text)):
        if not isinstance(node, ast.ImportFrom) or node.level != 1:
            continue
        if node.module is None:
            names.update(alias.name for alias in node.names)
        else:
            names.add(node.module.split(".")[0])
    return sorted(names)


def number(value):
    return f"{value:g}"


def point_text(point):
    return "(" + ", ".join(number(value) for value in point) + ")"


def stub_part_line(machine):
    """The stub's part line, or "" when the motion moves no part."""
    kind, height = machine.motion.kind, machine.footprint.height
    if kind not in records.PART_MOTIONS:
        return ""
    if kind == "iris":
        minimum = "tuple(value - 0.05 for value in records.hinge(machine))"
        maximum = "tuple(value + 0.05 for value in records.hinge(machine))"
        return f'    kit.join_part([kit.box({minimum}, {maximum}, "{STUB_PART_MATERIAL}")], machine, records.pivot(machine), records.hinge(machine))\n'
    box = f'kit.box((-0.25, -0.25, {number(height)}), (0.25, 0.25, {number(height + 0.5)}), "{STUB_PART_MATERIAL}")'
    if kind in ("spin", "swing"):
        return f"    kit.join_part([{box}], machine, records.pivot(machine))\n"
    return f"    kit.join_part([{box}], machine)\n"


def stub_script(machine):
    """The script a first round starts from: a placeholder box."""
    width, depth, height = machine.footprint.width, machine.footprint.depth, machine.footprint.height
    minimum = point_text((-width / 2, -depth / 2, 0.0))
    maximum = point_text((width / 2, depth / 2, height))
    return (
        f'"""{machine.model}. Replace this stub: build(machine) builds the model in Blender\'s\n'
        "frame (tools/models/kit.py, the module docstring). The grey box is a\n"
        "placeholder so the commands run before your first line, not a shape to\n"
        'keep."""\n'
        "\n"
        "from .. import kit, records  # noqa: F401\n"
        "\n"
        "\n"
        "def build(machine):\n"
        f"    kit.expect_footprint(machine, {width}, {depth}, {height})\n"
        f'    kit.join([kit.box({minimum}, {maximum}, "{STUB_BODY_MATERIAL}")], "body")\n'
        + stub_part_line(machine)
    )


def registry_text(models):
    """The lab's tools/models/machines/__init__.py."""
    entries = "".join(f'    "{name}": {name}.build,\n' for name in models)
    pairs = ", ".join(f'("{name}", {name})' for name in models)
    if len(models) == 1:
        pairs += ","
    return (
        '"""The machine scripts of this lab."""\n'
        "\n"
        f"from . import {', '.join(models)}\n"
        "\n"
        "MACHINES = {\n"
        f"{entries}"
        "}\n"
        "\n"
        "# The scripts' collision(b) sections, written by tools/make_models.py to\n"
        "# data/models/<model>.collision.sjson.\n"
        f'COLLISIONS = {{name: module.collision for name, module in ({pairs}) if hasattr(module, "collision")}}\n'
    )


def spoken_list(items):
    """a, b and c."""
    if len(items) < 2:
        return "".join(items)
    return ", ".join(items[:-1]) + " and " + items[-1]


def size_and_frame_line(model, machine):
    width, depth, height = machine.footprint.width, machine.footprint.depth, machine.footprint.height
    return (
        f"- `{model}`: the footprint is {width} by {depth} by {height} cells of 0.5 m ({number(width / 2)} m wide, {number(depth / 2)} m deep, {number(height / 2)} m high). "
        f"In Blender's frame as `tools/models/kit.py` documents (one unit per cell, the front at +X, Z up, the footprint centred) it spans x from {number(-width / 2)} to {number(width / 2)}, y from {number(-depth / 2)} to {number(depth / 2)} and z from 0 to {height}. "
        f"Nothing may leave it sideways (x within ±{number(width / 2 + check.TOLERANCE)}, y within ±{number(depth / 2 + check.TOLERANCE)}) or go below the ground (z at least {number(-check.TOLERANCE)}); a chimney, a mast or an antenna may rise above z {height}."
    )


def parts_line(model, machine):
    motion = machine.motion
    body = check.body_triangles_cap(machine)
    part = check.part_triangles_cap(machine)
    if motion.kind not in records.PART_MOTIONS:
        return f'- `{model}`: one mesh object named `body` under the sanity cap of {body} triangles (`kit.join(volumes, "body")`). It has no moving part, so there is no `part` object.'
    both = f"- `{model}`: one mesh object named `body` under the sanity cap of {body} triangles and one named `part` under the sanity cap of {part} triangles"
    if motion.kind == "iris":
        return (
            f"{both}: one blade, modelled shut, handed over with `kit.join_part(volumes, machine, records.pivot(machine), records.hinge(machine))` "
            f"(the pivot {point_text(records.pivot(machine))} and the hinge {point_text(records.hinge(machine))} in your frame). "
            f"The game draws it {motion.blades} times about the pivot and opens each copy about its own pin by {number(motion.amplitude)} turn times the open fraction."
        )
    if motion.kind in ("spin", "swing"):
        return (
            f"{both}, the moving part modelled at rest and handed over with `kit.join_part(volumes, machine, records.pivot(machine))`, built about the record's pivot "
            f"(`records.pivot(machine)` is {point_text(records.pivot(machine))} in your frame). "
            f"The game moves it by the record's `motion`: a {motion.kind} about its {motion.axis} axis, amplitude {number(motion.amplitude)} turn, period {number(motion.period_seconds)} s."
        )
    return (
        f"{both}, the moving part modelled at rest and handed over with `kit.join_part(volumes, machine)`. "
        f"The game moves it by the record's `motion`: a {motion.kind} along its {motion.axis} axis, amplitude {number(motion.amplitude)}, period {number(motion.period_seconds)} s."
    )


def check_command(machines, models, collision_models):
    first = models[0]
    text = (
        f"2. `python3 check.py` checks every model of this lab (`python3 check.py {first}` one): the triangle counts against the sanity caps, the materials, the emissive ones, the bounds, the object names, and `OK` or the problems. "
        "Nothing is finished while it reports a problem."
    )
    for model in models:
        if machines[model].motion.kind == "iris":
            text += f" For `{model}` it prints the iris's numbers and reports a copy leaving the footprint at any open fraction."
    for model in models:
        if model in collision_models:
            text += f" With `data/models/{model}.collision.sjson` it lists the collision volumes and reports one outside the footprint or inside an open cells box or a fixture box."
    return text


def model_previews(model, machine, views):
    """The previews render.py writes for one model."""
    names = list(EXTERIOR_VIEWS) + [entry["name"] for entry in views.get(model, [])]
    if machine.motion.kind == "iris":
        return f"for `{model}` every camera and `{model}_aperture` at open fractions 0, 0.5 and 1 (`{model}_<camera>_open_0.png`, `_open_0.5.png`, `_open_1.png`)"
    text = spoken_list([f"`{model}_{name}.png`" for name in names])
    if views.get(model):
        text += " (the cameras in `views.sjson`, metres in your frame: move them as the model takes shape)"
    return text


def render_command(machines, models, views):
    previews = "; ".join(model_previews(model, machines[model], views) for model in models)
    return (
        f"3. `tools/blender render.py` renders every model of this lab (`tools/blender render.py {models[0]}` one) into `previews/`: {previews}. "
        "A model with a collision file is rendered again with its volumes as magenta wires (`<model>_<camera>_collision.png`). "
        "If Blender complains about a display, run `xvfb-run -a tools/blender render.py`. "
        "Look at every preview with the Read tool and compare it with the references, then iterate. "
        "Expect several rounds of build, check, render, look before the model is right; do not hand back the first thing that passes the check."
    )


def lab_reference_models(models, machines):
    """The REFERENCE_MODELS entries the lab sees, (model, images): never
    one of the lab's models, and for a lab remaking one of a reference's
    fixtures only the reference's outside renders, captioned as showing
    the old fixture (work item 0275, Decision 1)."""
    entries = []
    for reference, images in REFERENCE_MODELS:
        if reference in models:
            continue
        record = records.machine_for_model(machines, reference)
        replaced = [machines[fixture.machine].model for fixture in record.fixtures if machines[fixture.machine].model in models]
        if replaced:
            note = f" (it shows the old {spoken_list(sorted({f'`{model}`' for model in replaced}))}, which this lab replaces)"
            images = tuple((file, caption + note) for file, caption in images if file not in REFERENCE_INSIDE_IMAGES)
        entries.append((reference, images))
    return entries


def reference_counts(model):
    """(body, part, materials) of the repository's data/models/<model>.obj,
    counted as check_model counts them."""
    _, objects = check.read_obj(REPOSITORY_ROOT / "data" / "models" / f"{model}.obj")
    body = objects.get("body", [])
    part = objects.get("part", [])
    materials = {material for material, _ in body + part if material}
    return sum(len(corners) - 2 for _, corners in body), sum(len(corners) - 2 for _, corners in part), len(materials)


def reference_models_text(references):
    """The {{reference_models}} slot: per reference its footprint, its
    counts and its renders under reference_models/."""
    if not references:
        return "None: this lab remakes a reference model."
    lines = []
    for model, images, footprint, (body, part, materials) in references:
        lines.append(f"- `{model}`: the footprint {footprint.width} by {footprint.depth} by {footprint.height} cells, {body} body triangles, {part} part triangles, {materials} materials")
        lines += [f"  - `{REFERENCE_MODELS_DIRECTORY}/{file}`: {caption}" for file, caption in images]
    return "\n".join(lines)


def brief_slots(machines, models, views, collision_models=(), references=()):
    """{{name}} to its text for the lab's models; references as
    (model, images, footprint, counts)."""
    names = [f"`{model}`" for model in models]
    parts = [parts_line(model, machines[model]) for model in models]
    parts.append(f"- At most {check.MATERIAL_LIMIT} materials over the body and the part of a model. The exporter triangulates and applies modifiers.")
    commands = [
        f"1. `tools/blender tools/make_models.py {' '.join(models)}` builds the models in Blender headless and writes `data/models/<model>.obj` and `.mtl` for each. Blender runs through Flatpak; the first start is slow. One name builds one model.",
        check_command(machines, models, collision_models),
        render_command(machines, models, views),
    ]
    return {
        "models": spoken_list(names),
        "size_and_frame": "\n".join(size_and_frame_line(model, machines[model]) for model in models),
        "parts": "\n".join(parts),
        "scripts": spoken_list([f"`tools/models/machines/{model}.py`" for model in models]),
        "commands": "\n".join(commands),
        "reference_models": reference_models_text(references),
    }


SLOT = re.compile(r"\{\{([A-Za-z0-9_]+)\}\}")


def fill_brief(template, slots):
    """The brief with every {{name}} replaced; refuses a [[...]] slot
    left and an unknown name."""
    if "[[" in template:
        line = template[: template.index("[[")].count("\n") + 1
        raise SystemExit(f"BRIEF has an unfilled [[...]] slot near line {line}")
    for name in SLOT.findall(template):
        if name not in slots:
            raise SystemExit(f"unknown slot {{{{{name}}}}}")
    return SLOT.sub(lambda match: slots[match.group(1)], template)


def unmentioned_images(brief, names):
    return [name for name in names if name not in brief]


def lab_directory(argument, lab_name, main_root):
    """The lab's directory: tmp/model_lab/<lab> of the main checkout, or
    the argument, which must be inside a tmp directory under it."""
    if argument is None:
        return main_root / "tmp" / "model_lab" / lab_name
    lab = pathlib.Path(argument).resolve()
    if main_root not in lab.parents or lab == main_root / "tmp":
        raise SystemExit(f"the lab must be under {main_root}: the Flatpak Blender does not see /tmp")
    parts = lab.relative_to(main_root).parts
    if "tmp" not in parts[:-1] or lab.name == "tmp" or parts[-2:] == ("tmp", "model_lab"):
        raise SystemExit(f"the lab must be inside a tmp directory under {main_root} and not tmp or tmp/model_lab itself, since --replace removes it")
    return lab


def refuse_unbuilt_lab(lab):
    """Stops unless the directory holds the lab.sjson every build writes
    last, so --replace never removes a directory this tool did not build
    (a hand built lab such as tmp/pod_lab, or a directory of labs)."""
    marker = lab / "lab.sjson"
    try:
        valid = marker.is_file() and {"models", "mode", "built_from"} <= set(sjson.load(marker))
    except Exception:
        valid = False
    if not valid:
        raise SystemExit(f"{lab} holds no lab.sjson: it is not a lab built by this tool, so --replace does not remove it")


def lab_file_text(models, mode, built_from):
    quoted = ", ".join(f'"{model}"' for model in models)
    return (
        "// The lab's models, its round and the commit its copies came from.\n"
        f"models = [{quoted}]\n"
        f'mode = "{mode}"\n'
        f'built_from = "{built_from}"\n'
    )


def git_output(*arguments):
    return subprocess.run(["git", "-C", str(REPOSITORY_ROOT), *arguments], check=True, capture_output=True, text=True).stdout.strip()


def main_checkout_root():
    return pathlib.Path(git_output("rev-parse", "--path-format=absolute", "--git-common-dir")).parent


def reference_images(directory):
    """The image file names of the directory, not recursive, sorted."""
    if not directory.is_dir():
        raise SystemExit(f"no reference directory {directory}")
    names = sorted(path.name for path in directory.iterdir() if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES)
    if not names:
        raise SystemExit(f"no image ({', '.join(IMAGE_SUFFIXES)}) in {directory}")
    return names


def read_views(lab_name):
    path = LAB_TOOLS / lab_name / "views.sjson"
    return sjson.load(path) if path.exists() else {}


def copy_into(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(source, target)


def write_scripts(staging, models, machines, rework):
    """The stubs, or with rework the scripts, their helpers and models."""
    scripts = staging / "tools" / "models" / "machines"
    for model in models:
        if not rework:
            (scripts / f"{model}.py").write_text(stub_script(machines[model]))
            continue
        source = REPOSITORY_ROOT / "tools" / "models" / "machines" / f"{model}.py"
        if not (REPOSITORY_ROOT / "data" / "models" / f"{model}.obj").exists() or not source.exists():
            raise SystemExit(f"--rework needs the accepted model of {model}")
        for name in [model] + helper_modules(source.read_text()):
            copy_into(source.parent / f"{name}.py", scripts / f"{name}.py")
        for suffix in (".obj", ".mtl", ".collision.sjson"):
            model_file = REPOSITORY_ROOT / "data" / "models" / f"{model}{suffix}"
            if model_file.exists():
                copy_into(model_file, staging / "data" / "models" / model_file.name)


def write_lab(staging, models, rework, brief_template, reference, images):
    """Fills the staging directory; returns the filled brief."""
    lab_name = models[0]
    for directory in ("tools/models/machines", "data/models", "reference", "previews"):
        (staging / directory).mkdir(parents=True, exist_ok=True)
    for path in COPIED_TOOLS:
        copy_into(REPOSITORY_ROOT / path, staging / path)
    for name in LAB_FILES:
        copy_into(LAB_TOOLS / name, staging / name)
    views = read_views(lab_name)
    if views:
        copy_into(LAB_TOOLS / lab_name / "views.sjson", staging / "views.sjson")
    for name in images:
        copy_into(reference / name, staging / "reference" / name)
    checkout_machines = records.load_machines(MACHINES_PATH)
    references = []
    for reference_model, reference_images in lab_reference_models(models, checkout_machines):
        for file, _ in reference_images:
            if not (BOOKLET / file).is_file():
                raise SystemExit(f"no reference model image {BOOKLET / file}")
            copy_into(BOOKLET / file, staging / REFERENCE_MODELS_DIRECTORY / file)
        footprint = records.machine_for_model(checkout_machines, reference_model).footprint
        references.append((reference_model, reference_images, footprint, reference_counts(reference_model)))
    machines_text = MACHINES_PATH.read_text()
    keys = REWORK_ROUND_STRIPPED_KEYS if rework else MODEL_ROUND_STRIPPED_KEYS
    (staging / "data" / "machines.sjson").write_text(lab_records_text(machines_text, models, keys, rework))
    (staging / "tools" / "models" / "machines" / "__init__.py").write_text(registry_text(models))
    machines = {model: records.machine_for_model(checkout_machines, model) for model in models}
    write_scripts(staging, models, machines, rework)
    collision_models = [model for model in models if (staging / "data" / "models" / f"{model}.collision.sjson").exists()]
    brief = fill_brief(brief_template, brief_slots(machines, models, views, collision_models, references))
    (staging / "BRIEF.md").write_text(brief)
    (staging / "lab.sjson").write_text(lab_file_text(models, "rework" if rework else "model", git_output("rev-parse", "HEAD")))
    return brief


def validate_lab(staging, models, stripped_keys):
    """The lab's records load, name every model with the checkout's
    footprint, and set none of the stripped keys."""
    lab_machines = records.load_machines(staging / "data" / "machines.sjson")
    checkout_machines = records.load_machines(MACHINES_PATH)
    lab_text = (staging / "data" / "machines.sjson").read_text()
    for model in models:
        machine = records.machine_for_model(lab_machines, model)
        if machine.footprint != records.machine_for_model(checkout_machines, model).footprint:
            raise SystemExit(f"the lab's footprint of {model} is not the checkout's")
        if "open_cells" in stripped_keys and machine.open_cells:
            raise SystemExit(f"the lab's record of {model} keeps open_cells")
        if "fixtures" in stripped_keys and machine.fixtures:
            raise SystemExit(f"the lab's record of {model} keeps fixtures")
        for block in record_blocks(lab_text, "model", model):
            if any(entry_key(line, stripped_keys) for line in block.splitlines()):
                raise SystemExit(f"the lab's record of {model} keeps a stripped key")


def argument_path(argument):
    return pathlib.Path(argument).resolve()


def build(arguments):
    models = parse_models(arguments.models)
    lab_name = models[0]
    brief_path = argument_path(arguments.brief) if arguments.brief else LAB_TOOLS / lab_name / "BRIEF.md"
    if not brief_path.is_file():
        raise SystemExit(f"no brief: copy tools/model_lab/brief_template.md to tools/model_lab/{lab_name}/BRIEF.md and fill its [[...]] slots, or pass --brief")
    reference = argument_path(arguments.reference)
    images = reference_images(reference)
    lab = lab_directory(arguments.lab, lab_name, main_checkout_root())
    if lab.exists() and not arguments.replace:
        raise SystemExit(f"{lab} exists (a modeller may be working in it): pass --replace to rebuild it")
    if lab.exists():
        refuse_unbuilt_lab(lab)
    lab.parent.mkdir(parents=True, exist_ok=True)
    staging = pathlib.Path(tempfile.mkdtemp(dir=lab.parent, prefix=lab.name + ".staging."))
    keys = REWORK_ROUND_STRIPPED_KEYS if arguments.rework else MODEL_ROUND_STRIPPED_KEYS
    try:
        brief = write_lab(staging, models, arguments.rework, brief_path.read_text(), reference, images)
        validate_lab(staging, models, keys)
        if lab.exists():
            shutil.rmtree(lab)
        os.rename(staging, lab)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    for path in sorted(path for path in lab.rglob("*") if path.is_file()):
        print(path)
    for name in unmentioned_images(brief, images):
        print(f"image {name} is not named in BRIEF.md")
    print(f"lab: {lab}")
    return 0


def replace_file(source, target):
    """target written as <target>.tmp and renamed over it."""
    temporary = target.with_name(target.name + ".tmp")
    shutil.copyfile(source, temporary)
    os.replace(temporary, target)


def copy_lab_models(lab, model):
    """The lab's model files into the checkout's data/models/."""
    lab_models = lab / "data" / "models"
    if lab_models.resolve() == (REPOSITORY_ROOT / "data" / "models").resolve():
        raise SystemExit(f"{lab} is this checkout, not a lab")
    for suffix in (".obj", ".mtl"):
        if not (lab_models / f"{model}{suffix}").exists():
            raise SystemExit(f"no {lab_models / (model + suffix)}: build the model in the lab first")
    for suffix in (".obj", ".mtl", ".collision.sjson"):
        source = lab_models / f"{model}{suffix}"
        if source.exists():
            replace_file(source, REPOSITORY_ROOT / "data" / "models" / source.name)
            print(f"copied {source.name}")


def record_difference(checkout_text, lab_text, model, keys):
    """The unified difference of the model's records, both stripped."""
    checkout = "".join(stripped_block(block, keys) for block in record_blocks(checkout_text, "model", model))
    lab = "".join(stripped_block(block, keys) for block in record_blocks(lab_text, "model", model))
    lines = list(difflib.unified_diff(checkout.splitlines(keepends=True), lab.splitlines(keepends=True), "checkout", "lab"))
    return "".join(lines) if lines else f"record of {model}: as the checkout's\n"


def preview(arguments):
    # The game's output follows in order only when ours is flushed first.
    sys.stdout.reconfigure(line_buffering=True)
    if REPOSITORY_ROOT.resolve() == main_checkout_root().resolve():
        raise SystemExit("preview copies the lab's models into data/models: run it from the item's worktree")
    lab = argument_path(arguments.lab)
    lab_file = sjson.load(lab / "lab.sjson")
    models = arguments.models or lab_file["models"]
    for model in models:
        parse_models(model)
    keys = REWORK_ROUND_STRIPPED_KEYS if lab_file["mode"] == "rework" else MODEL_ROUND_STRIPPED_KEYS
    checkout_text = MACHINES_PATH.read_text()
    lab_text = (lab / "data" / "machines.sjson").read_text()
    checkout_machines = records.load_machines(MACHINES_PATH)
    identifiers = []
    for model in models:
        copy_lab_models(lab, model)
        print(record_difference(checkout_text, lab_text, model, keys), end="")
        identifiers.append(records.machine_for_model(checkout_machines, model).id)
    for identifier in identifiers:
        result = subprocess.run(["./build.sh", "model-check", identifier], cwd=REPOSITORY_ROOT)
        print(f"model-check {identifier}: exit {result.returncode}")
    directory = REPOSITORY_ROOT / "tmp" / "model_preview" / lab.name
    environment = dict(os.environ, MODEL_PREVIEW_DIRECTORY=str(directory))
    result = subprocess.run(["tools/model_preview.sh", *identifiers], cwd=REPOSITORY_ROOT, env=environment)
    print(f"previews: {directory}")
    return result.returncode


def argument_parser():
    parser = argparse.ArgumentParser(description="The sealed modelling lab (work item 0214, doc/build.md, The workbench).")
    commands = parser.add_subparsers(dest="command", required=True)
    build_command = commands.add_parser("build", help="build a lab")
    build_command.add_argument("models", help="<model>[,<model>...], the first names the lab")
    build_command.add_argument("reference", help="the directory of the reference images")
    build_command.add_argument("--rework", action="store_true", help="a round on an accepted model")
    build_command.add_argument("--lab", help="the lab directory, inside a tmp directory under the main checkout")
    build_command.add_argument("--brief", help="the brief, tools/model_lab/<lab>/BRIEF.md by default")
    build_command.add_argument("--replace", action="store_true", help="rebuild an existing lab")
    build_command.set_defaults(handler=build)
    preview_command = commands.add_parser("preview", help="hand a lab's models to the game in this worktree")
    preview_command.add_argument("lab", help="the lab directory")
    preview_command.add_argument("models", nargs="*", help="the models, every model of lab.sjson by default")
    preview_command.set_defaults(handler=preview)
    return parser


def main():
    arguments = argument_parser().parse_args()
    return arguments.handler(arguments)


if __name__ == "__main__":
    sys.exit(main())
