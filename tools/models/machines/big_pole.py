"""The big pole (work item 0205): 1 by 1 by 6 cells, a power pole. A
four legged steel lattice mast on a yellow plinth, two brace frames at
uneven heights, climbing rungs as the scale cue, a cap and the insulator
on the axis where the wire meets it (WIRE_DROP below the top,
render_power.odin). No moving part. Blender frame of kit.py: x the
front, y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 1, 6)
    volumes = [
        kit.box((-0.30, -0.30, 0.0), (0.30, 0.30, 0.05), "hazard_black"),
        kit.box((-0.27, -0.27, 0.05), (0.27, 0.27, 0.20), "power_yellow"),
        kit.box((-0.26, -0.26, 5.60), (0.26, 0.26, 5.68), "steel_dark"),
        kit.cylinder((0.0, 0.0), 5.68, 5.92, 0.06, 6, "galvanised"),
    ]
    # The primary volume: the four legs.
    for x in (-0.22, 0.22):
        for y in (-0.22, 0.22):
            volumes.append(kit.box((x - 0.025, y - 0.025, 0.20), (x + 0.025, y + 0.025, 5.60), "steel"))
    # Brace frames: plates with their middles open.
    for height in (1.70, 3.90):
        frame = kit.box((-0.27, -0.27, height), (0.27, 0.27, height + 0.05), "steel_dark")
        kit.opening(frame, (-0.19, -0.19, height - 0.01), (0.19, 0.19, height + 0.06))
        volumes.append(frame)
    volumes += kit.rib_row("Z", 0.40, 2.20, 3, 0.04, (-0.24, -0.20, 0), (-0.20, 0.20, 0), "galvanised", kit.model_random(machine, "rungs"))
    kit.join(volumes, "body")
