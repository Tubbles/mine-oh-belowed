"""The iron chest (work item 0205): 1 by 1 by 1 cells, a chest. The
wooden chest's shape in logistics grey metal, yellow corner edges and
uneven ribs on the sides. No moving part. Blender frame of kit.py: x the
front, y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 1, 1)
    volumes = [
        kit.box((-0.44, -0.44, 0.0), (0.44, 0.44, 0.06), "steel_dark"),
        # The primary volume: the box and its lid.
        kit.box((-0.40, -0.40, 0.06), (0.40, 0.40, 0.64), "logistics_grey", bevel=0.03),
        kit.box((-0.43, -0.43, 0.64), (0.43, 0.43, 0.74), "steel_dark", bevel=0.02),
        kit.box((0.40, -0.06, 0.48), (0.45, 0.06, 0.66), "galvanised"),
    ]
    # The logistics accent: yellow corner edges.
    for x in (-0.39, 0.39):
        for y in (-0.39, 0.39):
            volumes.append(kit.box((x - 0.025, y - 0.025, 0.08), (x + 0.025, y + 0.025, 0.62), "power_yellow"))
    # Ribs on the side faces, two and three, spaced unevenly.
    volumes += kit.rib_row("X", -0.30, 0.30, 2, 0.03, (0, 0.40, 0.12), (0, 0.43, 0.58), "steel_dark", kit.model_random(machine, "positive_y_ribs"))
    volumes += kit.rib_row("X", -0.30, 0.30, 3, 0.03, (0, -0.43, 0.12), (0, -0.40, 0.58), "steel_dark", kit.model_random(machine, "negative_y_ribs"))
    kit.join(volumes, "body")
