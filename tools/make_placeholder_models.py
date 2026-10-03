#!/usr/bin/env python3
"""Write the placeholder machine models (work items 0055 and 0056) and
the player's limbs (work item 0066) to data/models/. The OBJ machines
(tools/models/machines/: the stone furnace and the burner mining drill
of work item 0204, the machines before oil of work item 0205) are made
by tools/make_models.py; this script writes the rest until work item
0206.

Usage: tools/make_placeholder_models.py

Only the standard library is used, and the output is deterministic: the
same script writes the same bytes. Each model is drawn in the game's axes
(x along the machine's width and its forward side, y up, z along its
depth) at 16 voxels per block for a machine of 1 by 1 blocks across and 8
otherwise, and written as a MagicaVoxel .vox file, which is z up: game
(x, y, z) is stored as vox (x, depth - 1 - z, y), depth being the game z
size, the mapping the loader (src/model_vox/model_vox.odin) undoes. Both are right
handed, so nothing is mirrored. The front of a machine is its +x side,
the side its rotation points at.

A machine whose motion (data/machines.sjson) moves a part also gets
<id>_part.vox: the moving part alone, the same size and frame as the body.
The placeholder palette: the body in its material's colour, a darker
base, and the moving part in a colour of its own.

The .vox subset written: the "VOX " header with version 150, a MAIN chunk
holding one SIZE, one XYZI and one RGBA chunk. Palette index i (1 to 255)
is RGBA entry i - 1. Glow colours (the ones made with glow()) take the
indices from 240 up, which the game draws emissive: they ignore the world
light and light up while the machine works. Every other colour takes the
indices from 1 up.
"""

import pathlib
import struct

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parent.parent
MODELS_DIRECTORY = REPOSITORY_ROOT / "data" / "models"
VOX_VERSION = 150
PALETTE_SIZE = 256
EMISSIVE_PALETTE_START = 240


def glow(colour):
    """A colour the game draws emissive (palette index 240 and up)."""
    return (*colour, "glow")


def is_glow(colour) -> bool:
    return len(colour) == 4


def darker(colour, factor=0.6):
    return tuple(int(channel * factor) for channel in colour)


IRON = (150, 150, 158)
IRON_DARK = (95, 95, 102)
STEEL = (112, 120, 134)
STEEL_DARK = (70, 75, 86)
DRILL_BODY = (150, 120, 70)
DRILL_RIM = (95, 75, 45)
DRILL_BIT = (200, 200, 205)
DRILL_BIT_TIP = (110, 110, 118)
BORE_DRILL_BODY = (110, 90, 130)
BORE_DRILL_RIM = (70, 55, 85)
FURNACE_MOUTH = (40, 36, 34)
CHIMNEY = (70, 70, 74)
BASE = (60, 60, 66)
MOVING = (210, 70, 50)
BLADE = (220, 220, 225)
CAPSULE_WHITE = (210, 212, 216)
CAPSULE_TOP = (200, 90, 40)
WINDOW = (40, 60, 90)
CRUSHER_BROWN = (130, 100, 70)
WASHER_BLUE = (70, 110, 160)
ALLOY_GREY = (100, 96, 104)
RECYCLER_GREEN = (90, 120, 70)
REFINERY_TAN = (150, 130, 90)
CRACKING_MAUVE = (130, 90, 110)
CHEMISTRY_GREEN = (110, 150, 110)
ELECTROLYSER_YELLOW = (170, 150, 60)
ELECTROLYTE = (90, 150, 190)
BUBBLE = (230, 240, 250)
TAR_DARK = (70, 64, 60)
FLARE_GREY = (120, 110, 100)
GENERATOR_BROWN = (110, 100, 80)
TURBINE_BLUE = (90, 120, 140)
INSULATOR = (230, 230, 220)
PAD_GREY = (120, 122, 128)
PAD_STRIPE = (220, 180, 40)
SUIT = (60, 110, 200)
SUIT_DARK = (38, 62, 110)
VISOR = (24, 30, 44)
BED_FRAME = (90, 92, 100)
BED_BLANKET = (70, 90, 130)
PILLOW = (220, 220, 210)

FIRE = glow((240, 150, 60))
FLAME = glow((255, 190, 80))
HEATER = glow((255, 110, 60))
PAD_LIGHT = glow((255, 80, 60))


class Model:
    """Voxels in game axes, keyed by (x, y, z), valued by a colour: an RGB
    tuple, or four entries for a glow colour."""

    def __init__(self, footprint: tuple[int, int, int], size: tuple[int, int, int] | None = None):
        """size, in voxels, replaces the size the footprint gives, for a
        frame that is not a whole number of blocks (the player set)."""
        width, height, depth = footprint
        self.voxels_per_block = 16 if width == 1 and depth == 1 else 8
        per_block = self.voxels_per_block
        self.size = size or (width * per_block, height * per_block, depth * per_block)
        self.voxels: dict[tuple[int, int, int], tuple] = {}

    def box(self, minimum: tuple[int, int, int], maximum: tuple[int, int, int], colour) -> None:
        """Fills the inclusive box. colour is a colour or a function of (x, y, z)."""
        for x in range(minimum[0], maximum[0] + 1):
            for y in range(minimum[1], maximum[1] + 1):
                for z in range(minimum[2], maximum[2] + 1):
                    self.set((x, y, z), colour(x, y, z) if callable(colour) else colour)

    def set(self, position: tuple[int, int, int], colour) -> None:
        for axis in range(3):
            if not 0 <= position[axis] < self.size[axis]:
                raise ValueError(f"voxel {position} outside {self.size}")
        self.voxels[position] = colour

    def clear(self, minimum: tuple[int, int, int], maximum: tuple[int, int, int]) -> None:
        for x in range(minimum[0], maximum[0] + 1):
            for y in range(minimum[1], maximum[1] + 1):
                for z in range(minimum[2], maximum[2] + 1):
                    self.voxels.pop((x, y, z), None)

    def cylinder(self, axis: int, centre: tuple[float, float], radius: float, start: int, end: int, colour) -> None:
        """A round bar along axis (0 x, 1 y, 2 z) from start to end
        inclusive. centre is on the other two axes in their order (y and z,
        x and z, or x and y), in voxel units where a voxel's middle is at
        its index plus a half. colour is a colour or a function of
        (x, y, z)."""
        first, second = [other for other in range(3) if other != axis]
        for along in range(start, end + 1):
            for a in range(self.size[first]):
                for b in range(self.size[second]):
                    if (a + 0.5 - centre[0]) ** 2 + (b + 0.5 - centre[1]) ** 2 <= radius * radius:
                        position = [0, 0, 0]
                        position[axis], position[first], position[second] = along, a, b
                        self.set(tuple(position), colour(*position) if callable(colour) else colour)

    def ring(self, axis: int, centre: tuple[float, float], outer: float, inner: float, start: int, end: int, colour) -> None:
        """Like cylinder, without the voxels inside the inner radius."""
        first, second = [other for other in range(3) if other != axis]
        for along in range(start, end + 1):
            for a in range(self.size[first]):
                for b in range(self.size[second]):
                    distance = (a + 0.5 - centre[0]) ** 2 + (b + 0.5 - centre[1]) ** 2
                    if inner * inner < distance <= outer * outer:
                        position = [0, 0, 0]
                        position[axis], position[first], position[second] = along, a, b
                        self.set(tuple(position), colour)


def chunk(identifier: bytes, content: bytes, children: bytes = b"") -> bytes:
    return identifier + struct.pack("<ii", len(content), len(children)) + content + children


def palette_of(model: Model, positions) -> dict:
    """Palette index per colour: plain colours from 1, glow colours from
    EMISSIVE_PALETTE_START, each in the order they first appear."""
    indices = {}
    plain, emissive = 1, EMISSIVE_PALETTE_START
    for position in positions:
        colour = model.voxels[position]
        if colour in indices:
            continue
        if is_glow(colour):
            indices[colour], emissive = emissive, emissive + 1
        else:
            indices[colour], plain = plain, plain + 1
    if plain > EMISSIVE_PALETTE_START or emissive > PALETTE_SIZE:
        raise ValueError("more than 239 colours or 16 glow colours")
    return indices


def encode_vox(model: Model) -> bytes:
    positions = sorted(model.voxels)
    indices = palette_of(model, positions)
    width, height, depth = model.size
    size = struct.pack("<iii", width, depth, height)
    voxels = bytearray(struct.pack("<i", len(positions)))
    for x, y, z in positions:
        voxels += struct.pack("<BBBB", x, depth - 1 - z, y, indices[model.voxels[(x, y, z)]])
    colours = {index: colour for colour, index in indices.items()}
    rgba = bytearray()
    for entry in range(PALETTE_SIZE):
        red, green, blue = colours[entry + 1][:3] if entry + 1 in colours else (0, 0, 0)
        rgba += struct.pack("<BBBB", red, green, blue, 255)
    children = chunk(b"SIZE", size) + chunk(b"XYZI", bytes(voxels)) + chunk(b"RGBA", bytes(rgba))
    return b"VOX " + struct.pack("<i", VOX_VERSION) + chunk(b"MAIN", b"", children)


def base_plate(model: Model, colour=BASE, inset: int = 0, thickness: int = 1) -> None:
    """The darker base over the footprint."""
    width, _, depth = model.size
    model.box((inset, 0, inset), (width - 1 - inset, thickness - 1, depth - 1 - inset), colour)


def spokes(model: Model, axis: int, centre: tuple[int, int], radius: int, start: int, end: int, colour) -> None:
    """A cross of two bars two voxels thick about an axis, centred on the
    voxel corner centre (on the other two axes in their order)."""
    first, second = [other for other in range(3) if other != axis]
    for offset in range(-radius, radius):
        for thickness in (-1, 0):
            for along in range(start, end + 1):
                for a, b in ((centre[0] + offset, centre[1] + thickness), (centre[0] + thickness, centre[1] + offset)):
                    position = [0, 0, 0]
                    position[axis], position[first], position[second] = along, a, b
                    model.set(tuple(position), colour)


# The drop capsule, 1 by 2 by 1 at 16 voxels per block.

def drop_capsule():
    """1 by 1 by 2: a round white capsule with a window and an orange nose."""
    model = Model((1, 2, 1))
    model.box((1, 0, 1), (14, 1, 14), BASE)
    model.cylinder(1, (8, 8), 6.5, 2, 20, CAPSULE_WHITE)
    model.cylinder(1, (8, 8), 5.5, 21, 24, CAPSULE_WHITE)
    model.cylinder(1, (8, 8), 4, 25, 27, CAPSULE_TOP)
    model.cylinder(1, (8, 8), 2.5, 28, 30, CAPSULE_TOP)
    model.box((14, 12, 6), (14, 16, 9), WINDOW)
    return {"": model}


# Furnaces, 2 by 2 by 2 and 3 by 2 by 2.

def steel_furnace():
    """A steel box with a band, a mouth with its glow and a tall chimney."""
    model = Model((2, 2, 2))
    base_plate(model, STEEL_DARK, 1)
    model.box((1, 1, 1), (14, 12, 14), STEEL)
    model.box((1, 9, 1), (14, 9, 14), STEEL_DARK)
    model.clear((13, 2, 5), (14, 7, 10))
    model.box((12, 2, 5), (12, 7, 10), FURNACE_MOUTH)
    model.box((12, 2, 6), (13, 4, 9), FIRE)
    model.box((2, 13, 2), (4, 15, 4), CHIMNEY)
    return {"": model}


def alloy_furnace():
    """3 by 2 by 2: a grey block with two glowing mouths and two chimneys."""
    model = Model((3, 2, 2))
    base_plate(model, BASE, 0)
    model.box((1, 1, 1), (22, 11, 14), ALLOY_GREY)
    for z in (2, 9):
        model.clear((22, 2, z), (22, 7, z + 4))
        model.box((21, 2, z), (21, 7, z + 4), FURNACE_MOUTH)
        model.box((21, 2, z + 1), (22, 3, z + 3), FIRE)
    for z in (2, 11):
        model.box((3, 12, z), (5, 15, z + 2), CHIMNEY)
    return {"": model}


# Drills.

def bore_drill():
    """4 by 4 by 4: a purple body with a tower and a bore head on top that
    spins (the part)."""
    model = Model((4, 4, 4))
    base_plate(model, BORE_DRILL_RIM, 0, 2)
    model.box((1, 2, 1), (30, 11, 30), BORE_DRILL_BODY)
    model.box((1, 12, 1), (30, 12, 30), BORE_DRILL_RIM)
    model.cylinder(1, (16, 16), 6, 13, 26, BORE_DRILL_BODY)
    model.cylinder(1, (16, 16), 7, 17, 18, BORE_DRILL_RIM)
    part = Model((4, 4, 4))
    part.cylinder(1, (16, 16), 3, 27, 30, DRILL_BIT_TIP)
    spokes(part, 1, (16, 16), 11, 28, 29, MOVING)
    return {"": model, "_part": part}


def core_sample_drill():
    """1 by 1 by 2: a tripod over the column with a rod that pumps."""
    model = Model((1, 2, 1))
    model.box((2, 0, 2), (13, 1, 13), BASE)
    for x, z in ((2, 2), (12, 2), (7, 12)):
        model.box((x, 2, z), (x + 1, 25, z + 1), DRILL_RIM)
    model.box((2, 26, 2), (13, 27, 13), DRILL_BODY)
    part = Model((1, 2, 1))
    part.box((7, 4, 7), (8, 29, 8), DRILL_BIT)
    part.box((5, 20, 5), (10, 23, 10), MOVING)
    return {"": model, "_part": part}


# The inserter's arm (work item 0175, src/model_arm.odin): six files of
# one frame, ARM_FRAME voxels at 25 mm, each holding one part in the
# authored pose: the arm straight up, the gripper's fingers pointing up.
# The joints lie on the frame's vertical centre line (x and z 12, a voxel
# corner): the shoulder at 22 voxels (0.55 m), the elbow 50 above it
# (1.25 m), the wrist 42 above that (1.05 m) and the hand between the
# fingertips 12 above the wrist (0.3 m); the shoulder, elbow and wrist
# turn about z. model_arm.odin holds the same numbers in metres. The finger
# is drawn twice, offset either side of z 12, so it is authored centred.
# Grimy steel and yellow warning paint with black hazard stripes; the work
# lamp on the wrist block glows while the arm moves.

ARM_FRAME = (24, 128, 24)
ARM_YELLOW = (206, 162, 40)
ARM_BLACK = (36, 34, 32)
ARM_STEEL = (118, 120, 124)
ARM_STEEL_DARK = (72, 74, 78)
ARM_LAMP = glow((255, 196, 120))


def grimy(colour):
    """The colour with a hashed grime: a few voxels darker, so the metal
    reads worn without a pattern."""
    def shade(x, y, z):
        hash_value = (x * 73856093 ^ y * 19349663 ^ z * 83492791) & 0xFFFF
        step = hash_value % 7
        return darker(colour, 0.72) if step == 0 else darker(colour, 0.86) if step < 3 else colour
    return shade


def hazard(x, y, z):
    """Diagonal yellow and black warning stripes, three voxels wide."""
    return grimy(ARM_YELLOW)(x, y, z) if (x + y + z) // 3 % 2 == 0 else ARM_BLACK


def arm_base():
    model = Model((1, 1, 1), ARM_FRAME)
    model.box((2, 0, 2), (21, 1, 21), hazard)
    model.box((4, 0, 4), (19, 1, 19), grimy(ARM_STEEL_DARK))
    for x, z in ((3, 3), (20, 3), (3, 20), (20, 20)):
        model.set((x, 2, z), ARM_BLACK)
    model.cylinder(1, (12, 12), 6, 2, 13, grimy(ARM_STEEL))
    model.cylinder(1, (12, 12), 7.5, 14, 15, grimy(ARM_STEEL_DARK))
    return model


def arm_turret():
    model = Model((1, 1, 1), ARM_FRAME)
    model.cylinder(1, (12, 12), 7, 16, 18, hazard)
    for z in (4, 18):
        model.box((8, 16, z), (15, 26, z + 1), grimy(ARM_YELLOW))
    for z in (3, 20):
        model.cylinder(2, (12, 22), 3.5, z, z, ARM_STEEL_DARK)
    model.box((3, 17, 9), (7, 23, 14), grimy(ARM_STEEL_DARK))
    return model


def arm_upper_arm():
    """Nothing lies below the shoulder joint (y 22): the segment stretches
    about the joint at a long reach, which would push anything below it
    into the base's collar (0207, the workbench's first finding). The hub
    sits just above the joint."""
    model = Model((1, 1, 1), ARM_FRAME)
    for z in (6, 16):
        model.box((9, 22, z), (14, 76, z + 1), grimy(ARM_YELLOW))
        model.box((9, 30, z), (14, 35, z + 1), hazard)
        model.cylinder(2, (12, 26), 4, z, z + 1, ARM_STEEL_DARK)
        model.cylinder(2, (12, 72), 4, z, z + 1, ARM_STEEL_DARK)
    return model


def arm_forearm():
    model = Model((1, 1, 1), ARM_FRAME)
    model.box((10, 68, 9), (13, 116, 14), grimy(ARM_STEEL))
    model.box((10, 104, 9), (13, 109, 14), hazard)
    model.cylinder(2, (12, 72), 4, 9, 14, grimy(ARM_STEEL_DARK))
    model.cylinder(2, (12, 114), 3, 9, 14, grimy(ARM_STEEL_DARK))
    return model


def arm_gripper():
    model = Model((1, 1, 1), ARM_FRAME)
    model.box((8, 112, 8), (15, 118, 15), grimy(ARM_STEEL_DARK))
    model.box((10, 114, 16), (13, 117, 16), ARM_LAMP)
    model.box((9, 119, 7), (14, 120, 16), grimy(ARM_STEEL))
    return model


def arm_finger():
    model = Model((1, 1, 1), ARM_FRAME)
    model.box((10, 119, 11), (13, 127, 12), grimy(ARM_STEEL))
    model.box((9, 126, 11), (14, 127, 12), ARM_BLACK)
    return model


def arm():
    return {
        "": arm_base(),
        "_turret": arm_turret(),
        "_upper_arm": arm_upper_arm(),
        "_forearm": arm_forearm(),
        "_gripper": arm_gripper(),
        "_finger": arm_finger(),
    }


# Crafting machines.

def crusher():
    """2 by 2 by 2: a hopper whose roller spins about z inside it."""
    model = Model((2, 2, 2))
    base_plate(model, BASE, 0)
    model.box((1, 1, 1), (14, 9, 14), CRUSHER_BROWN)
    model.box((1, 10, 1), (14, 14, 14), darker(CRUSHER_BROWN))
    model.clear((3, 10, 3), (12, 14, 12))
    part = Model((2, 2, 2))
    part.box((7, 11, 3), (8, 12, 12), BLADE)
    spokes(part, 2, (8, 12), 4, 4, 11, MOVING)
    return {"": model, "_part": part}


def washer():
    """3 by 2 by 2: a blue tub with a paddle wheel spinning about x."""
    model = Model((3, 2, 2))
    base_plate(model, BASE, 0)
    model.box((1, 1, 1), (22, 9, 14), WASHER_BLUE)
    model.box((1, 10, 1), (22, 12, 14), darker(WASHER_BLUE))
    model.clear((3, 10, 3), (20, 12, 12))
    model.box((3, 9, 3), (20, 9, 12), ELECTROLYTE)
    part = Model((3, 2, 2))
    spokes(part, 0, (12, 8), 4, 5, 18, MOVING)
    return {"": model, "_part": part}


def recycler():
    """2 by 2 by 2: a green box with a shredder disc that spins on top."""
    model = Model((2, 2, 2))
    base_plate(model, BASE, 0)
    model.box((1, 1, 1), (14, 10, 14), RECYCLER_GREEN)
    model.box((7, 11, 7), (8, 11, 8), darker(RECYCLER_GREEN))
    part = Model((2, 2, 2))
    spokes(part, 1, (8, 8), 5, 12, 13, MOVING)
    return {"": model, "_part": part}


def refinery():
    """5 by 3 by 5: two columns, a tank and a thin flare stack whose flame
    glows."""
    model = Model((5, 3, 5))
    base_plate(model, BASE, 0, 2)
    model.cylinder(1, (13, 13), 5, 2, 20, REFINERY_TAN)
    model.cylinder(1, (27, 15), 4, 2, 16, REFINERY_TAN)
    for y in (8, 14):
        model.cylinder(1, (13, 13), 5.5, y, y, darker(REFINERY_TAN))
    model.cylinder(0, (6, 30), 4, 6, 34, IRON)
    model.box((18, 12, 12), (22, 13, 14), IRON_DARK)
    model.cylinder(1, (34, 6), 1.5, 2, 20, IRON_DARK)
    model.box((33, 21, 5), (34, 23, 6), FLAME)
    return {"": model}


def cracking_unit():
    """3 by 3 by 3: a body with a column and a glowing heater window."""
    model = Model((3, 3, 3))
    base_plate(model, BASE, 0)
    model.box((2, 1, 2), (21, 10, 21), CRACKING_MAUVE)
    model.cylinder(1, (8, 16), 4, 11, 23, darker(CRACKING_MAUVE, 0.8))
    model.box((22, 3, 7), (22, 6, 16), HEATER)
    return {"": model}


def chemical_plant():
    """3 by 3 by 3: a green body with two tanks and a mixer that spins."""
    model = Model((3, 3, 3))
    base_plate(model, BASE, 0)
    model.box((2, 1, 2), (21, 12, 21), CHEMISTRY_GREEN)
    for z in (6, 18):
        model.cylinder(1, (6, z), 3, 13, 20, darker(CHEMISTRY_GREEN, 0.8))
    model.box((14, 13, 11), (15, 13, 12), darker(CHEMISTRY_GREEN))
    part = Model((3, 3, 3))
    part.box((14, 14, 11), (15, 17, 12), IRON_DARK)
    spokes(part, 1, (15, 12), 4, 14, 15, MOVING)
    return {"": model, "_part": part}


def electrolyser():
    """3 by 3 by 3: an open tank with electrodes; bubbles (the part) bob
    over the electrolyte."""
    model = Model((3, 3, 3))
    base_plate(model, BASE, 0)
    model.box((2, 1, 2), (21, 11, 21), ELECTROLYSER_YELLOW)
    model.clear((4, 9, 4), (19, 11, 19))
    model.box((4, 9, 4), (19, 9, 19), ELECTROLYTE)
    for x in (7, 15):
        model.box((x, 10, 11), (x + 1, 19, 12), IRON_DARK)
    model.box((7, 20, 11), (16, 21, 12), IRON_DARK)
    part = Model((3, 3, 3))
    for x, y, z in ((5, 11, 6), (10, 12, 15), (17, 11, 7), (12, 13, 5), (5, 12, 16), (17, 13, 17)):
        part.box((x, y, z), (x + 1, y + 1, z + 1), BUBBLE)
    return {"": model, "_part": part}


# Fluid machines.

def tar_pit_pump():
    """2 by 1 by 1: a small pump jack; its beam and head bob."""
    model = Model((2, 1, 1))
    model.box((0, 0, 1), (15, 0, 6), BASE)
    model.box((7, 1, 3), (8, 4, 4), TAR_DARK)
    model.box((0, 1, 2), (3, 3, 5), darker(TAR_DARK))
    model.box((14, 1, 3), (14, 1, 4), IRON_DARK)
    part = Model((2, 1, 1))
    part.box((1, 5, 3), (13, 5, 4), TAR_DARK)
    part.box((13, 3, 3), (15, 6, 4), MOVING)
    return {"": model, "_part": part}


def flare_stack():
    """1 by 3 by 1: a thin stack on a base with a glowing flame on top."""
    model = Model((1, 3, 1))
    model.box((3, 0, 3), (12, 3, 12), BASE)
    model.cylinder(1, (8, 8), 3, 4, 40, FLARE_GREY)
    model.cylinder(1, (8, 8), 4, 41, 42, darker(FLARE_GREY))
    model.cylinder(1, (8, 8), 2.5, 43, 45, FLAME)
    model.box((7, 46, 7), (8, 47, 8), FLAME)
    return {"": model}


def combustion_generator():
    """3 by 2 by 2: a body with an exhaust, and a flywheel on the front that
    spins about x."""
    model = Model((3, 2, 2))
    base_plate(model, BASE, 0)
    model.box((1, 1, 1), (17, 11, 14), GENERATOR_BROWN)
    model.box((3, 12, 3), (5, 15, 5), CHIMNEY)
    model.box((18, 7, 7), (18, 8, 8), IRON_DARK)
    part = Model((3, 2, 2))
    part.ring(0, (8, 8), 6.5, 5, 19, 20, MOVING)
    spokes(part, 0, (8, 8), 6, 19, 20, MOVING)
    return {"": model, "_part": part}


def fuel_generator():
    """2 by 2 by 2 (work item 0140): a small brown body with a glowing
    firebox at the front, a chimney at the back and a dynamo on top."""
    model = Model((2, 2, 2))
    base_plate(model, BASE, 0)
    model.box((1, 1, 1), (12, 10, 14), GENERATOR_BROWN)
    model.box((13, 1, 3), (14, 8, 12), FURNACE_MOUTH)
    model.box((15, 2, 5), (15, 5, 10), FIRE)
    model.box((2, 11, 2), (4, 15, 4), CHIMNEY)
    model.box((7, 11, 6), (11, 13, 11), IRON_DARK)
    return {"": model}


def hydro_turbine():
    """2 by 2 by 2: two side frames and a water wheel that spins about z."""
    model = Model((2, 2, 2))
    for z in (1, 13):
        model.box((1, 0, z), (14, 2, z + 1), TURBINE_BLUE)
        model.box((6, 3, z), (9, 9, z + 1), TURBINE_BLUE)
    model.box((7, 7, 3), (8, 8, 12), IRON_DARK)
    part = Model((2, 2, 2))
    part.ring(2, (8, 8), 7, 5.5, 4, 11, MOVING)
    spokes(part, 2, (8, 8), 6, 5, 10, darker(MOVING, 0.8))
    return {"": model, "_part": part}


# Power.

def substation():
    """2 by 3 by 2: a transformer box inside a frame of four posts."""
    model = Model((2, 3, 2))
    base_plate(model, BASE, 0, 2)
    for x in (1, 13):
        for z in (1, 13):
            model.box((x, 2, z), (x + 1, 21, z + 1), STEEL)
    model.box((1, 20, 1), (14, 21, 14), STEEL_DARK)
    model.clear((3, 20, 3), (12, 21, 12))
    model.box((4, 2, 4), (11, 12, 11), IRON)
    for x in (5, 9):
        model.box((x, 13, 7), (x + 1, 15, 8), INSULATOR)
    return {"": model}


# The launch pad.

def launch_pad():
    """9 by 2 by 9: a platform with a yellow square around the rocket's
    place and warning lights on the corners that glow while it works. The
    tower and the rocket are drawn by the game."""
    model = Model((9, 2, 9))
    model.box((0, 0, 0), (71, 2, 71), PAD_GREY)
    low, high = 24, 47
    model.box((low, 2, low), (high, 2, low + 1), PAD_STRIPE)
    model.box((low, 2, high - 1), (high, 2, high), PAD_STRIPE)
    model.box((low, 2, low), (low + 1, 2, high), PAD_STRIPE)
    model.box((high - 1, 2, low), (high, 2, high), PAD_STRIPE)
    for x in (1, 69):
        for z in (1, 69):
            model.box((x, 3, z), (x + 1, 4, z + 1), PAD_LIGHT)
    return {"": model}


def pod():
    """6 by 8 by 6 cells of 0.5 m (work item 0179): a white hull of about 3
    by 3 by 4 m on a base plate, an orange band and windows on the sides,
    a door opening on the front (+x) and a bed as a block inside, seen
    through the door."""
    model = Model((6, 8, 6))
    model.box((0, 0, 0), (47, 1, 47), BASE)
    model.box((2, 2, 2), (45, 57, 45), CAPSULE_WHITE)
    model.clear((4, 2, 4), (43, 55, 43))
    model.box((4, 58, 4), (43, 59, 43), CAPSULE_WHITE)
    model.box((14, 60, 14), (33, 61, 33), CAPSULE_TOP)
    model.box((2, 40, 2), (45, 43, 45), CAPSULE_TOP)
    model.clear((4, 40, 4), (43, 43, 43))
    for z in (2, 3, 44, 45):
        model.box((16, 24, z), (31, 33, z), WINDOW)
    model.clear((44, 2, 17), (45, 35, 30))
    model.box((44, 36, 16), (45, 37, 31), CAPSULE_TOP)
    model.box((8, 2, 6), (23, 7, 37), BED_FRAME)
    model.box((9, 8, 7), (22, 9, 30), BED_BLANKET)
    model.box((9, 8, 31), (22, 10, 36), PILLOW)
    return {"": model}


# The player (work item 0066): six limbs in one frame of 10 by 29 by 10
# voxels at 16 per block, about the 0.6 by 1.8 by 0.6 blocks of the
# collision box. Every limb file has the whole frame's size, so the limbs
# stand in place when drawn at the same transform; the game swings each
# about a pivot it takes from the limb's voxel bounds (the top of an arm
# or a leg, the bottom of the head). The front is +x, the right side +z.

PLAYER_FRAME = (10, 29, 10)


def player_limb() -> Model:
    return Model((1, 2, 1), size=PLAYER_FRAME)


def player_torso() -> Model:
    model = player_limb()
    model.box((3, 13, 2), (6, 22, 7), SUIT)
    model.box((3, 13, 2), (6, 13, 7), SUIT_DARK)
    return model


def player_head() -> Model:
    """A helmet with the darker visor on the front."""
    model = player_limb()
    model.box((2, 23, 2), (7, 28, 7), SUIT)
    model.box((7, 24, 3), (7, 26, 6), VISOR)
    return model


def player_arm(z: int) -> Model:
    """Two voxels square, a darker glove at the bottom."""
    model = player_limb()
    model.box((4, 12, z), (5, 22, z + 1), SUIT)
    model.box((4, 12, z), (5, 13, z + 1), SUIT_DARK)
    return model


def player_leg(z: int) -> Model:
    """Three voxels across, a darker boot at the bottom."""
    model = player_limb()
    model.box((3, 0, z), (6, 12, z + 2), SUIT)
    model.box((3, 0, z), (6, 2, z + 2), SUIT_DARK)
    return model


def player():
    return {
        "_torso": player_torso(),
        "_head": player_head(),
        "_arm_left": player_arm(0),
        "_arm_right": player_arm(8),
        "_leg_left": player_leg(2),
        "_leg_right": player_leg(5),
    }


MODELS = {
    "steel_furnace": steel_furnace,
    "drop_capsule": drop_capsule,
    "arm": arm,
    "bore_drill": bore_drill,
    "tar_pit_pump": tar_pit_pump,
    "flare_stack": flare_stack,
    "combustion_generator": combustion_generator,
    "fuel_generator": fuel_generator,
    "hydro_turbine": hydro_turbine,
    "substation": substation,
    "crusher": crusher,
    "washer": washer,
    "alloy_furnace": alloy_furnace,
    "recycler": recycler,
    "refinery": refinery,
    "cracking_unit": cracking_unit,
    "chemical_plant": chemical_plant,
    "electrolyser": electrolyser,
    "core_sample_drill": core_sample_drill,
    "launch_pad": launch_pad,
    "pod": pod,
    "player": player,
}


def main() -> None:
    MODELS_DIRECTORY.mkdir(parents=True, exist_ok=True)
    for name, make in MODELS.items():
        for suffix, model in make().items():
            path = MODELS_DIRECTORY / f"{name}{suffix}.vox"
            path.write_bytes(encode_vox(model))
            print(f"wrote {path.relative_to(REPOSITORY_ROOT)}")


if __name__ == "__main__":
    main()
