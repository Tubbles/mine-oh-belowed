"""The landing pod (work items 0179, 0198): 12 by 8 by 8 cells, the
record's width the front axis. A white hull with a sloped roof, the
cabin and the airlock hollowed out of it, two door openings with
pockets the hatches' panels rise into, the orange band, two windows,
the bed, a mast with a dish and a roof hatch as the scale cue. The
cavities and the door openings come from the record's open cells and
fixture boxes (records.py); nothing stands in an open cell or a fixture
box. No moving part. Blender frame of kit.py: x the front, y = -game z,
z up."""

from .. import kit, records

# The open cells boxes of the cabin (the first three) and the airlock.
CABIN_BOXES = (0, 1, 2)
AIRLOCK_BOX = 3
# The fixtures that are hatches: the outer door, then the inner one.
DOOR_FIXTURES = (0, 1)


def bounding_box(boxes):
    minimum = tuple(min(box[0][axis] for box in boxes) for axis in range(3))
    maximum = tuple(max(box[1][axis] for box in boxes) for axis in range(3))
    return minimum, maximum


def lowered(box, widen=0.0):
    """A cutter for a cavity: lowered 0.01 under the floor, widened on x."""
    (x0, y0, z0), (x1, y1, z1) = box
    return (x0 - widen, y0, z0 - 0.01), (x1 + widen, y1, z1)


def build_hull(machine):
    hull = kit.box((-6.0, -4.0, 0.0), (6.0, 4.0, 6.4), "science_white")
    slab = kit.box((-5.6, -3.4, 6.4), (5.6, 3.4, 8.0), "science_white")
    cabin = bounding_box([records.open_cell_box(machine, index) for index in CABIN_BOXES])
    kit.opening(hull, *lowered(cabin))
    kit.opening(hull, *lowered(records.open_cell_box(machine, AIRLOCK_BOX)))
    for index in DOOR_FIXTURES:
        door = records.fixture_box(machine, index)
        kit.opening(hull, *lowered(door, widen=0.01))
        # The pocket the hatch's panel rises into, through the hull's top
        # into the roof slab.
        centre = (door[0][0] + door[1][0]) / 2
        kit.opening(hull, (centre - 0.11, -0.9, 3.99), (centre + 0.11, 0.9, 6.41))
        kit.opening(slab, (centre - 0.11, -0.9, 6.39), (centre + 0.11, 0.9, 7.95))
    # The windows: over the bed and over the bench.
    kit.opening(hull, (-3.6, -4.01, 2.4), (-1.4, -2.99, 3.6))
    kit.opening(hull, (-3.0, 2.99, 2.4), (-1.2, 4.01, 3.6))
    return [
        # The primary volume: the hull and its roof.
        hull,
        slab,
        kit.wedge((-5.6, -4.0, 6.4), (5.6, -3.4, 8.0), "science_white", rise="+Y"),
        kit.wedge((-5.6, 3.4, 6.4), (5.6, 4.0, 8.0), "science_white", rise="-Y"),
        kit.wedge((-6.0, -3.4, 6.4), (-5.6, 3.4, 8.0), "science_white", rise="+X"),
        kit.wedge((5.6, -3.4, 6.4), (6.0, 3.4, 8.0), "science_white", rise="-X"),
        kit.box((-3.6, -3.55, 2.4), (-1.4, -3.45, 3.6), "soot"),
        kit.box((-3.0, 3.45, 2.4), (-1.2, 3.55, 3.6), "soot"),
    ]


def build_decks(machine):
    """Under the open boxes' shrunk bottom, on the crater floor."""
    cabin = bounding_box([records.open_cell_box(machine, index) for index in CABIN_BOXES])
    airlock = records.open_cell_box(machine, AIRLOCK_BOX)
    return [
        kit.box(cabin[0], (cabin[1][0], cabin[1][1], 0.015), "steel_dark"),
        kit.box(airlock[0], (airlock[1][0], airlock[1][1], 0.015), "steel_dark"),
    ]


def build_band():
    return [
        kit.box((-6.015, -4.015, 4.4), (6.015, -4.0, 4.8), "mining_ochre"),
        kit.box((-6.015, 4.0, 4.4), (6.015, 4.015, 4.8), "mining_ochre"),
        kit.box((6.0, -4.0, 4.4), (6.015, 4.0, 4.8), "mining_ochre"),
        kit.box((-6.015, -4.0, 4.4), (-6.0, 4.0, 4.8), "mining_ochre"),
    ]


def build_bed():
    """On its solid cells: frame, mattress, blanket, pillow."""
    return [
        kit.box((-4.95, -2.95, 0.0), (-1.05, -1.05, 0.30), "steel_dark"),
        kit.box((-4.9, -2.9, 0.30), (-1.1, -1.1, 0.42), "galvanised"),
        kit.box((-3.9, -2.92, 0.40), (-1.08, -1.08, 0.48), "fluids_teal"),
        kit.box((-4.8, -2.6, 0.42), (-4.2, -1.4, 0.52), "science_white"),
    ]


def build_door_trims(machine):
    """Yellow trims round the outer door on the front face and round the
    inner door on the airlock's face: each door's +x face."""
    trims = []
    for index in DOOR_FIXTURES:
        door = records.fixture_box(machine, index)
        (_, low, _), (face, high, top) = door
        trims += [
            kit.box((face, low - 0.25, 0.0), (face + 0.015, low, top + 0.25), "power_yellow"),
            kit.box((face, high, 0.0), (face + 0.015, high + 0.25, top + 0.25), "power_yellow"),
            kit.box((face, low - 0.25, top), (face + 0.015, high + 0.25, top + 0.25), "power_yellow"),
        ]
    return trims


def build_roof(machine):
    return [
        *kit.rib_row("Y", -3.4, 3.4, 3, 0.10, (-6.015, 0, 0.3), (-6.0, 0, 6.0), "steel", kit.model_random(machine, "back_ribs")),
        kit.cylinder((-4.0, 2.4), 8.0, 9.2, 0.06, 6, "galvanised"),
        kit.cone((-4.0, 2.4), 9.0, 9.3, 0.04, 0.35, 8, "galvanised"),
        # Scale cue: the roof hatch.
        *kit.hatch("+Z", (1.5, 0.0, 8.0), 1.2, 1.2, "steel"),
    ]


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 12, 8, 8)
    volumes = build_hull(machine) + build_decks(machine) + build_band() + build_bed() + build_door_trims(machine) + build_roof(machine)
    kit.join(volumes, "body")
