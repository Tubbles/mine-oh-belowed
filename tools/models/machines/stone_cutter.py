"""The stone cutter (work items 0196, 0205): 2 by 2 by 2 cells, a
burner crafting machine in stone and steel. A stone bodied saw bench in
a steel frame, the blade rising through a slot in the bench top under a
hood guard carried by a riving arm from the back, a fire door glowing on
the front while it cuts, a short chimney, and a hand wheel on the side
as the scale cue. The part is the blade with its hub and balance marks,
a vertical table saw blade spinning about Blender Y (the record's game z
axis) through the record's pivot. Blender frame of kit.py: x the front,
y = -game z, z up."""

from .. import kit, records


def build_body(machine):
    bench_top = kit.box((-0.92, -0.92, 1.10), (0.92, 0.92, 1.20), "steel")
    kit.opening(bench_top, (-0.50, -0.06, 1.09), (0.50, 0.06, 1.21))
    volumes = [
        kit.box((-0.95, -0.95, 0.0), (0.95, 0.95, 0.10), "steel_dark"),
        # The primary volume: the stone body and the bench top.
        kit.box((-0.85, -0.85, 0.10), (0.85, 0.85, 1.00), "stone", bevel=0.04),
        bench_top,
        # The fire door and its glow.
        kit.box((0.85, -0.28, 0.25), (0.90, 0.28, 0.65), "steel_dark"),
        kit.box((0.90, -0.20, 0.32), (0.92, 0.20, 0.40), "heat_glow"),
        # The hood guard over the blade, its riving arm and post.
        kit.box((-0.50, 0.05, 1.60), (0.50, 0.08, 2.04), "steel_dark"),
        kit.box((-0.50, -0.08, 1.60), (0.50, -0.05, 2.04), "steel_dark"),
        kit.box((-0.50, -0.08, 2.00), (0.50, 0.08, 2.04), "steel_dark"),
        kit.box((-0.85, -0.03, 1.98), (-0.50, 0.03, 2.04), "steel_dark"),
        kit.box((-0.85, -0.03, 1.20), (-0.79, 0.03, 2.04), "steel_dark"),
        kit.cylinder((-0.55, 0.55), 1.20, 1.80, 0.08, 8, "steel_dark"),
        # Scale cue: the hand wheel on its stem.
        kit.cylinder((0.30, 0.60), 0.85, 0.95, 0.03, 6, "steel", axis="Y"),
        kit.ring((0.30, 0.95, 0.60), 0.22, 0.03, "steel", axis="Y", sides=8, minor_sides=3),
    ]
    for x in (-0.88, 0.88):
        for y in (-0.88, 0.88):
            volumes.append(kit.box((x - 0.04, y - 0.04, 0.10), (x + 0.04, y + 0.04, 1.10), "steel"))
    kit.join(volumes, "body")


def build_part(machine):
    pivot = records.pivot(machine)
    pivot_x, _, pivot_z = pivot
    volumes = [
        kit.cylinder((pivot_x, pivot_z), -0.02, 0.02, 0.45, 12, "steel", axis="Y"),
        kit.cylinder((pivot_x, pivot_z), -0.04, 0.04, 0.10, 8, "steel_dark", axis="Y"),
        kit.box((pivot_x + 0.15, 0.02, pivot_z - 0.02), (pivot_x + 0.30, 0.025, pivot_z + 0.02), "hazard_black"),
        kit.box((pivot_x + 0.15, -0.025, pivot_z - 0.02), (pivot_x + 0.30, -0.02, pivot_z + 0.02), "hazard_black"),
    ]
    kit.join_part(volumes, machine, pivot)


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 2, 2, 2)
    build_body(machine)
    build_part(machine)
