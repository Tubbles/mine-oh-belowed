#!/usr/bin/env python3
"""Write the placeholder machine models (work item 0055) to data/models/.

Usage: tools/make_placeholder_models.py

Only the standard library is used, and the output is deterministic: the
same script writes the same bytes. Each model is drawn in the game's axes
(x along the machine's width and its forward side, y up, z along its
depth) at 8 voxels per block, and written as a MagicaVoxel .vox file,
which is z up: game (x, y, z) is stored as vox (x, depth - 1 - z, y),
depth being the game z size, the mapping the loader (src/model_vox.odin)
undoes. Both are right handed, so nothing is mirrored. The front of a machine is its +x side,
the side its rotation points at.

The .vox subset written: the "VOX " header with version 150, a MAIN chunk
holding one SIZE, one XYZI and one RGBA chunk. Palette index i (1 to 255)
is RGBA entry i - 1.
"""

import pathlib
import struct

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parent.parent
MODELS_DIRECTORY = REPOSITORY_ROOT / "data" / "models"
VOXELS_PER_BLOCK = 8
VOX_VERSION = 150
PALETTE_SIZE = 256

WOOD = (130, 88, 48)
WOOD_LIGHT = (150, 104, 58)
WOOD_DARK = (70, 45, 25)
METAL = (170, 170, 176)
DRILL_BODY = (150, 120, 70)
DRILL_RIM = (95, 75, 45)
DRILL_BIT = (200, 200, 205)
DRILL_BIT_TIP = (110, 110, 118)
ARROW = (240, 220, 80)
STONE = (120, 120, 124)
STONE_DARK = (98, 98, 102)
FURNACE_MOUTH = (40, 36, 34)
FURNACE_GLOW = (240, 150, 60)
CHIMNEY = (70, 70, 74)


class Model:
    """Voxels in game axes, keyed by (x, y, z), valued by an RGB colour."""

    def __init__(self, width: int, height: int, depth: int):
        self.size = (width, height, depth)
        self.voxels: dict[tuple[int, int, int], tuple[int, int, int]] = {}

    def box(self, minimum: tuple[int, int, int], maximum: tuple[int, int, int], colour) -> None:
        """Fills the inclusive box. colour is an RGB tuple or a function of (x, y, z)."""
        for x in range(minimum[0], maximum[0] + 1):
            for y in range(minimum[1], maximum[1] + 1):
                for z in range(minimum[2], maximum[2] + 1):
                    self.set((x, y, z), colour(x, y, z) if callable(colour) else colour)

    def set(self, position: tuple[int, int, int], colour: tuple[int, int, int]) -> None:
        for axis in range(3):
            if not 0 <= position[axis] < self.size[axis]:
                raise ValueError(f"voxel {position} outside {self.size}")
        self.voxels[position] = colour

    def clear(self, minimum: tuple[int, int, int], maximum: tuple[int, int, int]) -> None:
        for x in range(minimum[0], maximum[0] + 1):
            for y in range(minimum[1], maximum[1] + 1):
                for z in range(minimum[2], maximum[2] + 1):
                    self.voxels.pop((x, y, z), None)


def chunk(identifier: bytes, content: bytes, children: bytes = b"") -> bytes:
    return identifier + struct.pack("<ii", len(content), len(children)) + content + children


def encode_vox(model: Model) -> bytes:
    positions = sorted(model.voxels)
    palette: list[tuple[int, int, int]] = []
    for position in positions:
        if model.voxels[position] not in palette:
            palette.append(model.voxels[position])
    if len(palette) > PALETTE_SIZE - 1:
        raise ValueError("more than 255 colours")
    width, height, depth = model.size
    size = struct.pack("<iii", width, depth, height)
    voxels = bytearray(struct.pack("<i", len(positions)))
    for x, y, z in positions:
        voxels += struct.pack("<BBBB", x, depth - 1 - z, y, palette.index(model.voxels[(x, y, z)]) + 1)
    rgba = bytearray()
    for index in range(PALETTE_SIZE):
        red, green, blue = palette[index] if index < len(palette) else (0, 0, 0)
        rgba += struct.pack("<BBBB", red, green, blue, 255)
    children = chunk(b"SIZE", size) + chunk(b"XYZI", bytes(voxels)) + chunk(b"RGBA", bytes(rgba))
    return b"VOX " + struct.pack("<i", VOX_VERSION) + chunk(b"MAIN", b"", children)


def blocks(width: int, height: int, depth: int) -> Model:
    return Model(width * VOXELS_PER_BLOCK, height * VOXELS_PER_BLOCK, depth * VOXELS_PER_BLOCK)


def burner_mining_drill() -> Model:
    """2 by 2 by 2: a squat body, a motor housing at the back with the drill
    bit standing out of it, and an arrow on the top pointing at the output
    side (+x)."""
    model = blocks(2, 2, 2)
    model.box((1, 0, 1), (14, 6, 14), DRILL_BODY)
    model.box((1, 7, 1), (14, 7, 14), DRILL_RIM)
    model.box((2, 8, 4), (7, 11, 11), DRILL_RIM)
    model.box((4, 12, 7), (5, 14, 8), DRILL_BIT)
    model.box((4, 15, 7), (5, 15, 8), DRILL_BIT_TIP)
    model.box((9, 8, 7), (10, 8, 8), ARROW)
    model.box((11, 8, 5), (11, 8, 10), ARROW)
    model.box((12, 8, 6), (12, 8, 9), ARROW)
    model.box((13, 8, 7), (13, 8, 8), ARROW)
    return model


def stone_texture(x: int, y: int, z: int):
    return STONE_DARK if (x * 7 + y * 3 + z * 5) % 5 == 0 else STONE


def stone_furnace() -> Model:
    """2 by 2 by 2: a stone box with a dark mouth on the front (+x), an
    orange glow patch at the bottom of the mouth, and a chimney."""
    model = blocks(2, 2, 2)
    model.box((1, 0, 1), (14, 12, 14), stone_texture)
    model.clear((13, 2, 5), (14, 7, 10))
    model.box((12, 2, 5), (12, 7, 10), FURNACE_MOUTH)
    model.box((12, 2, 6), (13, 3, 9), FURNACE_GLOW)
    model.box((3, 13, 3), (5, 15, 5), CHIMNEY)
    return model


def plank_texture(x: int, y: int, z: int):
    return WOOD_LIGHT if y % 2 == 0 else WOOD


def wooden_chest() -> Model:
    """1 by 1 by 1: a plank box with a dark lid line and a latch on the
    front (+x)."""
    model = blocks(1, 1, 1)
    model.box((1, 0, 1), (6, 5, 6), plank_texture)
    model.box((1, 4, 1), (6, 4, 6), WOOD_DARK)
    model.box((7, 3, 3), (7, 4, 4), METAL)
    return model


MODELS = {
    "burner_mining_drill": burner_mining_drill,
    "stone_furnace": stone_furnace,
    "wooden_chest": wooden_chest,
}


def main() -> None:
    MODELS_DIRECTORY.mkdir(parents=True, exist_ok=True)
    for name, make in MODELS.items():
        path = MODELS_DIRECTORY / f"{name}.vox"
        path.write_bytes(encode_vox(make()))
        print(f"wrote {path.relative_to(REPOSITORY_ROOT)}")


if __name__ == "__main__":
    main()
