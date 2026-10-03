"""The electric mining drill (work item 0205): 3 by 3 by 3 cells, mining
ochre. A housing on two skid rails with a bore in its top, a four
legged mast over it with climbing rungs as the scale cue, an output
chute and the cyan strip on the front, vents on a side and the teal
mining fluid inlet at the back port. The part is the motor, shaft and
bit, pumping down along y into the bore (no pivot). Blender frame of
kit.py: x the front, y = -game z, z up."""

from .. import kit, records


def build_body(machine):
    (_, inlet_y, inlet_z), _ = records.port_face(machine, records.port(machine, "input_mining_fluid"))
    housing = kit.box((-1.30, -1.30, 0.14), (1.30, 1.30, 1.00), "mining_ochre", bevel=0.05)
    kit.cut(housing, kit.cylinder((0.0, 0.0), 0.50, 1.10, 0.30, 12, "soot"))
    volumes = [
        kit.box((-1.45, 1.10, 0.0), (1.45, 1.40, 0.14), "steel_dark"),
        kit.box((-1.45, -1.40, 0.0), (1.45, -1.10, 0.14), "steel_dark"),
        housing,
        kit.cylinder((0.0, 0.0), 0.50, 0.52, 0.29, 8, "soot"),
        kit.box((-0.55, -0.55, 2.80), (0.55, 0.55, 2.92), "steel_dark"),
        kit.box((1.30, -0.25, 0.20), (1.45, 0.25, 0.45), "galvanised"),
        kit.cylinder((inlet_y, inlet_z), -1.50, -1.30, 0.13, 8, "fluids_teal", axis="X"),
        kit.strip("+X", (1.30, 0.70, 0.80), 0.50, 0.05, "electric_glow"),
    ]
    # The mast: four legs and their side braces at uneven heights.
    for x in (-0.45, 0.45):
        for y in (-0.45, 0.45):
            volumes.append(kit.box((x - 0.04, y - 0.04, 1.00), (x + 0.04, y + 0.04, 2.80), "steel"))
    for z in (1.60, 2.25):
        volumes.append(kit.box((-0.41, 0.41, z - 0.03), (0.41, 0.49, z + 0.03), "steel"))
        volumes.append(kit.box((-0.41, -0.49, z - 0.03), (0.41, -0.41, z + 0.03), "steel"))
    volumes += kit.rib_row("Z", 1.20, 2.70, 3, 0.04, (-0.47, -0.41, 0), (-0.43, 0.41, 0), "galvanised", kit.model_random(machine, "rungs"))
    volumes += kit.rib_row("X", -0.90, 0.70, 4, 0.04, (0, 1.30, 0.35), (0, 1.33, 0.80), "steel", kit.model_random(machine, "vents"))
    kit.join(volumes, "body")


def build_part(machine):
    volumes = [
        kit.box((-0.25, -0.22, 2.15), (0.25, 0.22, 2.55), "galvanised", bevel=0.03),
        kit.strip("+X", (0.25, 0.0, 2.45), 0.30, 0.04, "electric_glow"),
        kit.cylinder((0.0, 0.0), 1.25, 2.15, 0.07, 8, "steel"),
        kit.cone((0.0, 0.0), 0.95, 1.25, 0.0, 0.18, 8, "mining_ochre"),
    ]
    kit.join_part(volumes, machine)


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 3, 3, 3)
    build_body(machine)
    build_part(machine)
