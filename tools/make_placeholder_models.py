#!/usr/bin/env python3
"""Write the placeholder machine models (work items 0055 and 0056) and
the player's limbs (work item 0066) to data/models/.

Usage: tools/make_placeholder_models.py

Only the standard library is used, and the output is deterministic: the
same script writes the same bytes. Each model is drawn in the game's axes
(x along the machine's width and its forward side, y up, z along its
depth) at 16 voxels per block for a machine of 1 by 1 blocks across and 8
otherwise, and written as a MagicaVoxel .vox file, which is z up: game
(x, y, z) is stored as vox (x, depth - 1 - z, y), depth being the game z
size, the mapping the loader (src/model_vox.odin) undoes. Both are right
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


WOOD = (130, 88, 48)
WOOD_LIGHT = (150, 104, 58)
WOOD_DARK = (70, 45, 25)
METAL = (170, 170, 176)
IRON = (150, 150, 158)
IRON_DARK = (95, 95, 102)
STEEL = (112, 120, 134)
STEEL_DARK = (70, 75, 86)
DRILL_BODY = (150, 120, 70)
DRILL_RIM = (95, 75, 45)
DRILL_BIT = (200, 200, 205)
DRILL_BIT_TIP = (110, 110, 118)
ELECTRIC_DRILL_BODY = (80, 120, 150)
ELECTRIC_DRILL_RIM = (50, 75, 95)
BORE_DRILL_BODY = (110, 90, 130)
BORE_DRILL_RIM = (70, 55, 85)
ARROW = (240, 220, 80)
STONE = (120, 120, 124)
STONE_DARK = (98, 98, 102)
FURNACE_MOUTH = (40, 36, 34)
CHIMNEY = (70, 70, 74)
BASE = (60, 60, 66)
MOVING = (210, 70, 50)
BLADE = (220, 220, 225)
CAPSULE_WHITE = (210, 212, 216)
CAPSULE_TOP = (200, 90, 40)
WINDOW = (40, 60, 90)
CRATE = (120, 84, 50)
TEAL = (70, 130, 130)
CRUSHER_BROWN = (130, 100, 70)
WASHER_BLUE = (70, 110, 160)
ALLOY_GREY = (100, 96, 104)
RECYCLER_GREEN = (90, 120, 70)
REFINERY_TAN = (150, 130, 90)
CRACKING_MAUVE = (130, 90, 110)
CHEMISTRY_GREEN = (110, 150, 110)
GASIFIER_BROWN = (120, 100, 80)
ELECTROLYSER_YELLOW = (170, 150, 60)
ELECTROLYTE = (90, 150, 190)
BUBBLE = (230, 240, 250)
LAB_WHITE = (200, 204, 210)
LAB_GLASS = (150, 190, 220)
PUMP_BLUE = (80, 130, 170)
OFFSHORE_BLUE = (70, 120, 160)
TAR_DARK = (70, 64, 60)
BOILER_RED = (150, 80, 60)
ENGINE_GREEN = (90, 110, 90)
TANK_GREY = (140, 140, 150)
FLARE_GREY = (120, 110, 100)
GENERATOR_BROWN = (110, 100, 80)
TURBINE_BLUE = (90, 120, 140)
POLE_WOOD = (120, 90, 60)
INSULATOR = (230, 230, 220)
PAD_GREY = (120, 122, 128)
PAD_STRIPE = (220, 180, 40)
SWITCH_BODY = (80, 80, 86)
INSERTER_POST = (70, 70, 76)
SUIT = (60, 110, 200)
SUIT_DARK = (38, 62, 110)
VISOR = (24, 30, 44)

FIRE = glow((240, 150, 60))
FLAME = glow((255, 190, 80))
LAMP_LIGHT = glow((255, 240, 170))
LAB_LIGHT = glow((90, 150, 240))
SIGNAL_GREEN = glow((80, 220, 100))
GOLD_LATCH = glow((220, 180, 60))
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
        its index plus a half."""
        first, second = [other for other in range(3) if other != axis]
        for along in range(start, end + 1):
            for a in range(self.size[first]):
                for b in range(self.size[second]):
                    if (a + 0.5 - centre[0]) ** 2 + (b + 0.5 - centre[1]) ** 2 <= radius * radius:
                        position = [0, 0, 0]
                        position[axis], position[first], position[second] = along, a, b
                        self.set(tuple(position), colour)

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


def stone_texture(x: int, y: int, z: int):
    return STONE_DARK if (x * 7 + y * 3 + z * 5) % 5 == 0 else STONE


def plank_texture(x: int, y: int, z: int):
    return WOOD_LIGHT if y % 2 == 0 else WOOD


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


# Chests and crates, 1 by 1 by 1 at 16 voxels per block.

def wooden_chest():
    """A plank box with a dark lid line and a latch on the front (+x)."""
    model = Model((1, 1, 1))
    model.box((2, 0, 2), (13, 11, 13), plank_texture)
    model.box((2, 8, 2), (13, 8, 13), WOOD_DARK)
    model.box((14, 6, 7), (14, 9, 8), METAL)
    return {"": model}


def iron_chest():
    """An iron box with dark corner bands and a latch on the front."""
    model = Model((1, 1, 1))
    model.box((2, 0, 2), (13, 11, 13), IRON)
    for x, z in ((2, 2), (2, 13), (13, 2), (13, 13)):
        model.box((x, 0, z), (x, 11, z), IRON_DARK)
    model.box((2, 8, 2), (13, 8, 13), IRON_DARK)
    model.box((14, 6, 7), (14, 9, 8), METAL)
    return {"": model}


def schematic_crate():
    """A wooden crate whose latch glows while it holds a schematic."""
    model = Model((1, 1, 1))
    model.box((1, 0, 1), (14, 11, 14), CRATE)
    for y in (0, 11):
        model.box((1, y, 1), (14, y, 14), WOOD_DARK)
    model.box((15, 5, 6), (15, 8, 9), GOLD_LATCH)
    return {"": model}


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

def stone_furnace():
    """A stone box with a dark mouth on the front (+x), a glow patch at the
    bottom of the mouth, and a chimney."""
    model = Model((2, 2, 2))
    model.box((1, 0, 1), (14, 12, 14), stone_texture)
    model.clear((13, 2, 5), (14, 7, 10))
    model.box((12, 2, 5), (12, 7, 10), FURNACE_MOUTH)
    model.box((12, 2, 6), (13, 3, 9), FIRE)
    model.box((3, 13, 3), (5, 15, 5), CHIMNEY)
    return {"": model}


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

def burner_mining_drill():
    """2 by 2 by 2: a squat body with an arrow on the top towards the output
    side (+x) and a frame at the back whose drill head pumps (the part)."""
    model = Model((2, 2, 2))
    model.box((1, 0, 1), (14, 6, 14), DRILL_BODY)
    model.box((1, 7, 1), (14, 7, 14), DRILL_RIM)
    for z in (3, 12):
        model.box((2, 8, z), (3, 15, z), DRILL_RIM)
        model.box((6, 8, z), (7, 15, z), DRILL_RIM)
    model.box((2, 15, 3), (7, 15, 12), DRILL_RIM)
    model.box((9, 8, 7), (10, 8, 8), ARROW)
    model.box((11, 8, 5), (11, 8, 10), ARROW)
    model.box((12, 8, 6), (12, 8, 9), ARROW)
    model.box((13, 8, 7), (13, 8, 8), ARROW)
    part = Model((2, 2, 2))
    part.box((3, 11, 5), (6, 13, 10), MOVING)
    part.box((4, 8, 7), (5, 10, 8), DRILL_BIT)
    part.box((4, 14, 7), (5, 14, 8), DRILL_BIT_TIP)
    return {"": model, "_part": part}


def electric_mining_drill():
    """3 by 3 by 3: a blue body with a derrick whose drill head pumps."""
    model = Model((3, 3, 3))
    base_plate(model, ELECTRIC_DRILL_RIM, 0)
    model.box((1, 1, 1), (22, 9, 22), ELECTRIC_DRILL_BODY)
    model.box((1, 10, 1), (22, 10, 22), ELECTRIC_DRILL_RIM)
    for x in (6, 16):
        for z in (6, 16):
            model.box((x, 11, z), (x + 1, 22, z + 1), ELECTRIC_DRILL_RIM)
    model.box((6, 23, 6), (17, 23, 17), ELECTRIC_DRILL_RIM)
    part = Model((3, 3, 3))
    part.box((9, 14, 9), (14, 17, 14), MOVING)
    part.box((11, 11, 11), (12, 13, 12), DRILL_BIT)
    part.box((11, 18, 11), (12, 22, 12), DRILL_BIT_TIP)
    return {"": model, "_part": part}


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


# Inserters, 1 by 1 by 1: a base and a post; the arm (the part) points at
# the pickup side (-x) at rest and swings over the right side to the drop
# side. The gripper's bottom middle is the motion's hand, (2/16, 7/16,
# 8/16) of a block.

def inserter_model(arm_colour):
    def make():
        model = Model((1, 1, 1))
        model.box((3, 0, 3), (12, 1, 12), BASE)
        model.box((6, 2, 6), (9, 8, 9), INSERTER_POST)
        part = Model((1, 1, 1))
        part.box((7, 9, 7), (8, 12, 8), arm_colour)
        part.box((2, 11, 7), (8, 12, 8), arm_colour)
        part.box((1, 7, 6), (3, 10, 9), darker(arm_colour, 0.7))
        return {"": model, "_part": part}
    return make


# Crafting machines.

def assembler():
    """3 by 2 by 3: a teal body with a wheel on the top that spins."""
    model = Model((3, 2, 3))
    base_plate(model, BASE, 0)
    model.box((1, 1, 1), (22, 10, 22), TEAL)
    model.box((1, 11, 1), (22, 11, 22), darker(TEAL))
    model.box((11, 12, 11), (12, 12, 12), darker(TEAL))
    part = Model((3, 2, 3))
    part.ring(1, (12, 12), 8, 6, 13, 14, MOVING)
    spokes(part, 1, (12, 12), 7, 13, 14, MOVING)
    return {"": model, "_part": part}


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


def lab():
    """3 by 2 by 3: a white body with a glass top whose lights glow."""
    model = Model((3, 2, 3))
    base_plate(model, BASE, 0)
    model.box((1, 1, 1), (22, 8, 22), LAB_WHITE)
    model.box((5, 9, 5), (18, 13, 18), LAB_GLASS)
    model.box((5, 14, 5), (18, 14, 18), LAB_WHITE)
    for x, z in ((5, 5), (5, 17), (17, 5), (17, 17)):
        model.box((x, 9, z), (x + 1, 13, z + 1), LAB_WHITE)
    model.box((19, 10, 10), (19, 12, 13), LAB_LIGHT)
    model.box((10, 10, 4), (13, 12, 4), LAB_LIGHT)
    model.box((10, 10, 19), (13, 12, 19), LAB_LIGHT)
    model.box((10, 15, 10), (13, 15, 13), LAB_LIGHT)
    return {"": model}


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


def wood_gasifier():
    """2 by 3 by 2: a drum on a base with a glowing fire door and a pipe."""
    model = Model((2, 3, 2))
    base_plate(model, BASE, 0)
    model.cylinder(1, (8, 8), 6, 1, 17, GASIFIER_BROWN)
    model.cylinder(1, (8, 8), 4, 18, 20, darker(GASIFIER_BROWN))
    model.cylinder(1, (8, 8), 1.5, 21, 23, IRON_DARK)
    model.box((13, 2, 4), (14, 6, 11), FURNACE_MOUTH)
    model.box((15, 3, 5), (15, 5, 10), FIRE)
    return {"": model}


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

def offshore_pump():
    """2 by 1 by 1: a blue body at the back (the port side), an intake pipe
    to the front going down into the water, and a motor that bobs."""
    model = Model((2, 1, 1))
    model.box((0, 0, 1), (8, 5, 6), OFFSHORE_BLUE)
    model.box((9, 2, 3), (15, 3, 4), IRON)
    model.box((14, 0, 3), (15, 1, 4), IRON)
    part = Model((2, 1, 1))
    part.box((2, 6, 2), (6, 7, 5), MOVING)
    return {"": model, "_part": part}


def pump():
    """2 by 1 by 1: a pipe along x with flanges and a motor that bobs."""
    model = Model((2, 1, 1))
    model.box((1, 0, 2), (2, 1, 5), BASE)
    model.box((13, 0, 2), (14, 1, 5), BASE)
    model.box((0, 2, 2), (15, 5, 5), PUMP_BLUE)
    for x in (0, 15):
        model.box((x, 1, 1), (x, 6, 6), darker(PUMP_BLUE))
    part = Model((2, 1, 1))
    part.box((5, 6, 2), (10, 7, 5), MOVING)
    return {"": model, "_part": part}


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


def boiler():
    """3 by 2 by 2: a drum along x with a glowing firebox at the front and
    a chimney at the back."""
    model = Model((3, 2, 2))
    base_plate(model, BASE, 0)
    model.cylinder(0, (8, 8), 6, 1, 18, BOILER_RED)
    for x in (4, 12):
        model.cylinder(0, (8, 8), 6.5, x, x, darker(BOILER_RED))
    model.box((19, 1, 3), (22, 9, 12), FURNACE_MOUTH)
    model.box((23, 2, 5), (23, 5, 10), FIRE)
    model.box((3, 13, 7), (5, 15, 9), CHIMNEY)
    return {"": model}


def steam_engine():
    """3 by 2 by 5: a cylinder along z on a base, and a flywheel on the +x
    side that spins about x."""
    model = Model((3, 2, 5))
    base_plate(model, BASE, 0)
    model.cylinder(2, (8, 7), 5, 3, 26, ENGINE_GREEN)
    for z in (3, 26):
        model.cylinder(2, (8, 7), 6, z, z, darker(ENGINE_GREEN))
    model.box((14, 1, 29), (15, 8, 30), IRON_DARK)
    part = Model((3, 2, 5))
    part.ring(0, (8, 30), 7, 5.5, 18, 19, MOVING)
    spokes(part, 0, (8, 30), 6, 18, 19, MOVING)
    part.box((16, 7, 29), (17, 8, 30), IRON_DARK)
    return {"": model, "_part": part}


def storage_tank():
    """3 by 3 by 3: a round grey tank on a base with two bands."""
    model = Model((3, 3, 3))
    base_plate(model, BASE, 1)
    model.cylinder(1, (12, 12), 11, 1, 21, TANK_GREY)
    for y in (6, 16):
        model.cylinder(1, (12, 12), 11, y, y, darker(TANK_GREY, 0.8))
    model.cylinder(1, (12, 12), 8, 22, 22, darker(TANK_GREY, 0.9))
    return {"": model}


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

def small_pole():
    """1 by 3 by 1: a wooden post with a cross arm and two insulators."""
    model = Model((1, 3, 1))
    model.box((7, 0, 7), (8, 44, 8), POLE_WOOD)
    model.box((2, 41, 7), (13, 42, 8), darker(POLE_WOOD))
    for x in (2, 12):
        model.box((x, 43, 7), (x + 1, 45, 8), INSULATOR)
    return {"": model}


def big_pole():
    """1 by 6 by 1: a steel lattice mast with a cross arm."""
    model = Model((1, 6, 1))
    for x in (4, 10):
        for z in (4, 10):
            model.box((x, 0, z), (x + 1, 88, z + 1), STEEL)
    for y in range(8, 88, 10):
        model.box((4, y, 4), (11, y, 11), STEEL_DARK)
        model.clear((6, y, 6), (9, y, 9))
    model.box((0, 86, 7), (15, 87, 8), STEEL_DARK)
    for x in (0, 14):
        model.box((x, 88, 7), (x + 1, 91, 8), INSULATOR)
    return {"": model}


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


def power_switch():
    """1 by 1 by 1: a box with a lever and a light that glows while on."""
    model = Model((1, 1, 1))
    model.box((3, 0, 3), (12, 9, 12), SWITCH_BODY)
    model.box((7, 10, 7), (8, 13, 8), METAL)
    model.box((13, 5, 6), (13, 8, 9), SIGNAL_GREEN)
    return {"": model}


def lamp():
    """1 by 1 by 1: a post with a head that glows while lit."""
    model = Model((1, 1, 1))
    model.box((5, 0, 5), (10, 1, 10), BASE)
    model.box((7, 2, 7), (8, 8, 8), IRON_DARK)
    model.box((5, 9, 5), (10, 13, 10), LAMP_LIGHT)
    model.box((4, 14, 4), (11, 15, 11), IRON_DARK)
    return {"": model}


# Logistics and the launch pad.

def splitter():
    """1 by 1 by 2 (one along the flow, two across): side rails and a gate
    beam over the belt surfaces the belt renderer draws."""
    model = Model((1, 1, 2))
    for z in (0, 15):
        model.box((0, 0, z), (7, 2, z), IRON_DARK)
        model.box((3, 3, z), (4, 5, z), IRON_DARK)
    model.box((3, 6, 0), (4, 6, 15), PAD_STRIPE)
    return {"": model}


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
    "wooden_chest": wooden_chest,
    "iron_chest": iron_chest,
    "stone_furnace": stone_furnace,
    "steel_furnace": steel_furnace,
    "drop_capsule": drop_capsule,
    "schematic_crate": schematic_crate,
    "burner_inserter": inserter_model((150, 110, 70)),
    "inserter": inserter_model((220, 190, 60)),
    "filter_inserter": inserter_model((150, 90, 190)),
    "fast_inserter": inserter_model((70, 130, 220)),
    "long_inserter": inserter_model((200, 80, 60)),
    "burner_mining_drill": burner_mining_drill,
    "electric_mining_drill": electric_mining_drill,
    "bore_drill": bore_drill,
    "splitter": splitter,
    "offshore_pump": offshore_pump,
    "boiler": boiler,
    "steam_engine": steam_engine,
    "storage_tank": storage_tank,
    "pump": pump,
    "tar_pit_pump": tar_pit_pump,
    "flare_stack": flare_stack,
    "combustion_generator": combustion_generator,
    "hydro_turbine": hydro_turbine,
    "small_pole": small_pole,
    "big_pole": big_pole,
    "substation": substation,
    "power_switch": power_switch,
    "lamp": lamp,
    "assembler_1": assembler,
    "crusher": crusher,
    "washer": washer,
    "alloy_furnace": alloy_furnace,
    "recycler": recycler,
    "refinery": refinery,
    "cracking_unit": cracking_unit,
    "chemical_plant": chemical_plant,
    "wood_gasifier": wood_gasifier,
    "electrolyser": electrolyser,
    "core_sample_drill": core_sample_drill,
    "launch_pad": launch_pad,
    "lab": lab,
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
