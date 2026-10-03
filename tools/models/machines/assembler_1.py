"""Assembler 1 (work item 0205): 3 by 3 by 2 cells, a crafting machine
in the production colours (DESIGN.md, Art direction): a grey bevelled
housing with yellow corner posts and a dark deck, a window on the front
with the cyan state strip over it, a hatch on a side as the scale cue
and vents on the other. The part is the turntable with two unequal arms
and a yellow tool head, spinning about Z through the record's pivot.
Blender frame of kit.py: x the front, y = -game z, z up."""

from .. import kit, records


def build_body(machine):
    housing = kit.box((-1.30, -1.30, 0.10), (1.30, 1.30, 1.20), "logistics_grey", bevel=0.05)
    kit.opening(housing, (1.15, -0.70, 0.35), (1.35, 0.30, 0.95))
    volumes = [
        kit.box((-1.45, -1.45, 0.0), (1.45, 1.45, 0.10), "steel_dark"),
        housing,
        kit.box((-1.36, -1.36, 1.20), (1.36, 1.36, 1.28), "steel_dark"),
        kit.strip("+X", (1.30, -0.20, 1.05), 0.90, 0.05, "electric_glow"),
    ]
    for x in (-1.28, 1.28):
        for y in (-1.28, 1.28):
            volumes.append(kit.box((x - 0.04, y - 0.04, 0.10), (x + 0.04, y + 0.04, 1.24), "power_yellow"))
    volumes += kit.hatch("+Y", (0.20, 1.30, 0.55), 0.55, 0.60, "steel")
    volumes += kit.rib_row("X", -0.90, 0.40, 3, 0.04, (0, -1.33, 0.40), (0, -1.30, 0.95), "steel", kit.model_random(machine, "vents"))
    kit.join(volumes, "body")


def build_part(machine):
    pivot = records.pivot(machine)
    centre = (pivot[0], pivot[1])
    volumes = [
        kit.cylinder(centre, 1.32, 1.42, 0.70, 12, "steel_dark"),
        kit.box((pivot[0], pivot[1] - 0.06, 1.42), (pivot[0] + 0.62, pivot[1] + 0.06, 1.52), "galvanised"),
        kit.box((pivot[0] - 0.45, pivot[1] - 0.06, 1.42), (pivot[0], pivot[1] + 0.06, 1.52), "galvanised"),
        kit.box((pivot[0] + 0.48, pivot[1] - 0.09, 1.52), (pivot[0] + 0.64, pivot[1] + 0.09, 1.70), "power_yellow"),
        kit.cylinder(centre, 1.42, 1.60, 0.16, 8, "steel"),
    ]
    kit.join_part(volumes, machine, pivot)


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 3, 3, 2)
    build_body(machine)
    build_part(machine)
