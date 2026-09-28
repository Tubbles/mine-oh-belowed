#!/usr/bin/env python3
"""Write the placeholder block textures and item icons (work item 0060) to
data/textures/blocks/ and data/textures/items/, and the UI icons (work
item 0071) to data/ui/icons/.

Usage: tools/make_placeholder_textures.py

Only the standard library is used (zlib and struct write the PNG files),
and the output is deterministic: the same script and the same data files
write the same bytes. Every file is 16 by 16 pixels, 8 bit RGBA.

The ids come from data/blocks.sjson and data/items.sjson, read with small
regular expressions rather than an SJSON parser. That works because both
files are regular: every block entry has its id line before its texture
line, `texture = {top = [r, g, b], side = [...], bottom = [...]}` on one
line, and every item entry sits on one line with its id first and its
category and places_block as `key = "value"`. A new block or item gets a
texture on the next run.

Blocks: <id>.png holds the side pattern and serves every face group;
<id>_top.png and <id>_bottom.png are written where the data gives the
group a colour of its own, and <id>_side.png where the side differs from
the plain file (grass: dirt with a green fringe). The pattern follows the
material family taken from the id: noise per family, ore blobs in the
ore's colour over stone, bark grain and a ring top for logs, mottled
leaves, a grass top over a dirt side, bricks and mortar. Ground cover
(work item 0082: tufts, tall grass, flowers, dead bushes, reeds) is a
plant silhouette on transparent texels, drawn on the cross quads. The
torch is a stick with a flame head on transparent texels: the post
shows the stick, the item icon the whole torch.

Stone, the ores, leaves and water (work item 0088) use isotropic noise
only (isotropic_field: white noise blurred by a round Gaussian), with
no rows or diagonals, since the chunk shader turns and mirrors their
tiles per block and a field of them must not stripe.

Items: by category, coloured from a table of the common materials (a word
of the id picks it) or a colour hashed from the id: plates as rounded
rectangles, ores as lumps, gears as toothed rings, tools as simple
silhouettes, machines as a box with a darker base, science packs as a
flask. Tools stand upright: the handle vertical, the head at the top
(a pickaxe's crescent across it, a hammer's head reaching to the right).
An item that places a block shows the block's plain texture.

UI icons (the ui family): one file per name in UI_ICON_NAMES, which must
match the Ui_Icon enum in src/ui_theme.odin (a test checks the files).
Gamepad buttons are drawn by position (the face button's dot lit in the
accent among four), bumpers carry L1 or R1, triggers LT or RT and sticks
an L or an R in a 3 by 5 pixel font, the key is a blank dark key cap the game draws the
key's name on, and the categories and screens are small pictures.

The whole set is a placeholder: hand made art replaces the files later.
"""

import functools
import math
import pathlib
import re
import struct
import zlib

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA_DIRECTORY = REPOSITORY_ROOT / "data"
BLOCK_TEXTURES_DIRECTORY = DATA_DIRECTORY / "textures" / "blocks"
ITEM_TEXTURES_DIRECTORY = DATA_DIRECTORY / "textures" / "items"
UI_ICONS_DIRECTORY = DATA_DIRECTORY / "ui" / "icons"
SIZE = 16
TRANSPARENT = (0, 0, 0, 0)
FALLBACK_STONE = (128, 128, 128)

BLOCK_ID_PATTERN = re.compile(r'^\s*id = "([a-z0-9_]+)"', re.MULTILINE)
BLOCK_TEXTURE_PATTERN = re.compile(
    r"texture = \{top = \[(\d+), (\d+), (\d+)\], side = \[(\d+), (\d+), (\d+)\], bottom = \[(\d+), (\d+), (\d+)\]\}"
)
ITEM_LINE_PATTERN = re.compile(r'^\s*\{id = "([a-z0-9_]+)"(.*)\}\s*$', re.MULTILINE)
ITEM_FIELD_PATTERN = re.compile(r'\b(category|places_block) = "([a-z0-9_]+)"')

MATERIAL_COLOURS = {
    "iron": (160, 160, 168),
    "copper": (204, 112, 60),
    "tin": (206, 204, 192),
    "lead": (92, 98, 116),
    "zinc": (168, 182, 188),
    "nickel": (190, 184, 150),
    "gold": (232, 190, 60),
    "aluminium": (212, 216, 224),
    "steel": (116, 128, 146),
    "coal": (44, 44, 48),
    "stone": (128, 128, 128),
    "glass": (176, 216, 232),
    "wood": (150, 104, 58),
    "bronze": (176, 128, 64),
    "brass": (200, 170, 80),
}

# Words that name a material by another word: the ore minerals and the
# wooden things.
MATERIAL_ALIASES = {
    "hematite": "iron",
    "chalcopyrite": "copper",
    "cassiterite": "tin",
    "galena": "lead",
    "sphalerite": "zinc",
    "pentlandite": "nickel",
    "bauxite": "aluminium",
    "alumina": "aluminium",
    "wooden": "wood",
    "plank": "wood",
    "stick": "wood",
    "log": "wood",
    "charcoal": "coal",
    "quartz": "glass",
}

CIRCUIT_BOARD = (40, 120, 64)
CIRCUIT_TRACE = (210, 170, 70)
PAPER = (200, 214, 232)
PAPER_LINE = (70, 90, 140)
MAGNET_RED = (200, 50, 44)
CHARGE_RED = (180, 56, 40)
FUSE = (60, 56, 50)
SAPLING_GREEN = (80, 150, 60)
STEM_GREEN = (70, 130, 52)
REED_HEAD = (110, 72, 40)


# Deterministic hashing.


def hash_integer(value: int) -> int:
    """splitmix64, as the game's own atlas noise."""
    value = (value + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
    value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
    return value ^ (value >> 31)


def hash_text(text: str) -> int:
    return hash_integer(zlib.crc32(text.encode()))


def random_unit(key: str, x: int, y: int) -> float:
    """A value in [0, 1) fixed by the key and the texel."""
    return hash_integer(hash_text(key) ^ (y << 16) ^ x) / 2**64


def noise(key: str, x: int, y: int, amplitude: int) -> int:
    return int(random_unit(key, x, y) * (2 * amplitude + 1)) - amplitude


def smooth_noise(key: str, x: int, y: int, cell: int, amplitude: int) -> int:
    """Value noise on a grid of cell texels, bilinear between the corners,
    wrapping at the tile edge so neighbouring blocks join."""
    cells = SIZE // cell
    left, top = x // cell, y // cell
    fraction_x, fraction_y = (x % cell) / cell, (y % cell) / cell

    def corner(column: int, row: int) -> float:
        return random_unit(key + "/smooth", column % cells, row % cells)

    upper = corner(left, top) * (1 - fraction_x) + corner(left + 1, top) * fraction_x
    lower = corner(left, top + 1) * (1 - fraction_x) + corner(left + 1, top + 1) * fraction_x
    value = upper * (1 - fraction_y) + lower * fraction_y
    return int((value * 2 - 1) * amplitude)


ISOTROPIC_WIDTHS = ((2.0, 0.6), (1.0, 0.4))


def gaussian_blur(values: list, width: float) -> list:
    """values blurred by a round Gaussian of the given standard deviation
    in texels, wrapping at the tile edge so neighbouring blocks join."""
    reach = int(3 * width)
    kernel = [(offset_x, offset_y, math.exp(-(offset_x**2 + offset_y**2) / (2 * width**2))) for offset_y in range(-reach, reach + 1) for offset_x in range(-reach, reach + 1)]
    total = sum(weight for _, _, weight in kernel)
    return [[sum(weight * values[(y + offset_y) % SIZE][(x + offset_x) % SIZE] for offset_x, offset_y, weight in kernel) / total for x in range(SIZE)] for y in range(SIZE)]


@functools.cache
def isotropic_field(key: str, widths: tuple = ISOTROPIC_WIDTHS) -> tuple:
    """White noise blurred round at each (width, weight) and summed, then
    stretched to [0, 1]: smooth, without rows, diagonals or a grid."""
    white = [[random_unit(key + "/white", x, y) for x in range(SIZE)] for y in range(SIZE)]
    layers = [(gaussian_blur(white, width), weight) for width, weight in widths]
    summed = [[sum(layer[y][x] * weight for layer, weight in layers) for x in range(SIZE)] for y in range(SIZE)]
    lowest = min(min(row) for row in summed)
    highest = max(max(row) for row in summed)
    return tuple(tuple((value - lowest) / (highest - lowest) for value in row) for row in summed)


def isotropic_noise(key: str, x: int, y: int, amplitude: int) -> int:
    """isotropic_field as a shift of up to amplitude either way."""
    return int((isotropic_field(key)[y][x] * 2 - 1) * amplitude)


# Colours.


def clamp_channel(value: float) -> int:
    return max(0, min(255, int(round(value))))


def shifted(colour, amount: int) -> tuple:
    return tuple(clamp_channel(channel + amount) for channel in colour[:3])


def scaled(colour, factor: float) -> tuple:
    return tuple(clamp_channel(channel * factor) for channel in colour[:3])


def mixed(first, second, weight: float) -> tuple:
    return tuple(clamp_channel(a * (1 - weight) + b * weight) for a, b in zip(first[:3], second[:3]))


def opaque(colour) -> tuple:
    return (*colour[:3], 255)


def hash_colour(text: str) -> tuple:
    """A moderately saturated colour from the id."""
    value = hash_text(text)
    hue = (value % 360) / 360
    red, green, blue = (0.5 + 0.35 * math.cos(2 * math.pi * (hue + offset)) for offset in (0, 1 / 3, 2 / 3))
    return (clamp_channel(red * 220), clamp_channel(green * 220), clamp_channel(blue * 220))


def material_colour(item_id: str):
    """The colour of the first word of the id the table knows, or None."""
    for word in item_id.split("_"):
        word = MATERIAL_ALIASES.get(word, word)
        if word in MATERIAL_COLOURS:
            return MATERIAL_COLOURS[word]
    return None


# Images: lists of SIZE rows of SIZE RGBA tuples.


def blank() -> list:
    return [[TRANSPARENT] * SIZE for _ in range(SIZE)]


def pattern(texel) -> list:
    """An image whose texel (x, y) is texel(x, y), opaque."""
    return [[opaque(texel(x, y)) for x in range(SIZE)] for y in range(SIZE)]


def encode_png(image: list) -> bytes:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    rows = b"".join(b"\x00" + bytes(channel for texel in row for channel in texel) for row in image)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


# Block patterns. Each takes the face colour and a key for its noise.


def noisy(colour, key: str, amplitude: int, blotch: int = 0) -> list:
    return pattern(lambda x, y: shifted(colour, noise(key, x, y, amplitude) + smooth_noise(key, x, y, 4, blotch)))


def stone_texel(colour, key: str, x: int, y: int) -> tuple:
    return shifted(colour, noise(key, x, y, 8) + isotropic_noise(key, x, y, 16))


def stone_pattern(colour, key: str) -> list:
    return pattern(lambda x, y: stone_texel(colour, key, x, y))


def rock_pattern(colour, key: str) -> list:
    """Stone with horizontal strata (its side keeps its orientation,
    keep_orientation in blocks.sjson)."""

    def texel(x: int, y: int) -> tuple:
        base = shifted(colour, noise(key, x, y, 10) + smooth_noise(key, x, y, 4, 14))
        return shifted(base, -12 if (y + x // 6) % 5 == 0 else 0)

    return pattern(texel)


# The share of an ore tile's texels in blobs, and the blobs' width.
ORE_BLOB_SHARE = 0.2
ORE_BLOB_WIDTHS = ((1.6, 1.0),)


def ore_pattern(colour, key: str, stone) -> list:
    """Round blobs of ore colour over stone: the highest ORE_BLOB_SHARE of
    an isotropic field."""
    image = stone_pattern(stone, key + "/stone")
    field = isotropic_field(key + "/blob", ORE_BLOB_WIDTHS)
    threshold = sorted(value for row in field for value in row)[int(SIZE * SIZE * (1 - ORE_BLOB_SHARE))]
    for y in range(SIZE):
        for x in range(SIZE):
            if field[y][x] >= threshold:
                image[y][x] = opaque(shifted(colour, noise(key, x, y, 14)))
    return image


def dirt_pattern(colour, key: str) -> list:
    def texel(x: int, y: int) -> tuple:
        speck = random_unit(key + "/speck", x, y)
        amount = -22 if speck < 0.08 else 18 if speck > 0.95 else 0
        return shifted(colour, noise(key, x, y, 10) + smooth_noise(key, x, y, 4, 8) + amount)

    return pattern(texel)


def grass_top_pattern(colour, key: str) -> list:
    def texel(x: int, y: int) -> tuple:
        blade = random_unit(key + "/blade", x, y)
        amount = 20 if blade > 0.85 else -16 if blade < 0.1 else 0
        return shifted(colour, noise(key, x, y, 8) + smooth_noise(key, x, y, 4, 10) + amount)

    return pattern(texel)


def grass_side_pattern(top, dirt, key: str) -> list:
    """Dirt with a fringe of grass hanging down one to four texels."""
    image = dirt_pattern(dirt, key + "/dirt")
    fringe = grass_top_pattern(top, key + "/fringe")
    for x in range(SIZE):
        depth = 2 + int(random_unit(key, x, 400) * 3)
        for y in range(depth):
            image[y][x] = fringe[y][x]
    return image


def bark_pattern(colour, key: str) -> list:
    """Vertical grain: each column its own shade, with darker cracks."""

    def texel(x: int, y: int) -> tuple:
        column = noise(key + "/column", x, 0, 12)
        crack = -30 if random_unit(key + "/crack", x, y // 3) < 0.12 else 0
        return shifted(colour, column + crack + noise(key, x, y, 5))

    return pattern(texel)


def rings_pattern(colour, bark, key: str) -> list:
    """Year rings around the centre, a rim of bark."""

    def texel(x: int, y: int) -> tuple:
        if x in (0, SIZE - 1) or y in (0, SIZE - 1):
            return shifted(bark, noise(key, x, y, 6))
        distance = math.hypot(x - 7.5, y - 7.5)
        ring = -20 if int(distance) % 3 == 0 else 0
        return shifted(colour, ring + noise(key, x, y, 5))

    return pattern(texel)


def leaves_pattern(colour, key: str) -> list:
    def texel(x: int, y: int) -> tuple:
        value = random_unit(key, x, y)
        amount = -40 if value < 0.12 else -16 if value < 0.45 else 18 if value > 0.85 else 0
        return shifted(colour, amount + isotropic_noise(key, x, y, 10))

    return pattern(texel)


def water_pattern(colour, key: str) -> list:
    return pattern(lambda x, y: shifted(colour, isotropic_noise(key, x, y, 10) + noise(key, x, y, 3)))


def tar_pattern(colour, key: str) -> list:
    """Dark with a few glossy texels."""

    def texel(x: int, y: int) -> tuple:
        gloss = 36 if random_unit(key + "/gloss", x, y) > 0.94 else 0
        return shifted(colour, gloss + noise(key, x, y, 4) + smooth_noise(key, x, y, 8, 6))

    return pattern(texel)


def concrete_pattern(colour, key: str) -> list:
    def texel(x: int, y: int) -> tuple:
        pore = -24 if random_unit(key + "/pore", x, y) < 0.05 else 0
        return shifted(colour, pore + noise(key, x, y, 5))

    return pattern(texel)


def brick_pattern(colour, key: str) -> list:
    """Bricks of 8 by 4 texels, every other row shifted by half a brick,
    in pale mortar."""
    mortar = mixed(colour, (200, 196, 186), 0.7)

    def texel(x: int, y: int) -> tuple:
        row = y // 4
        if y % 4 == 3 or (x + (4 if row % 2 else 0)) % 8 == 7:
            return shifted(mortar, noise(key, x, y, 4))
        return shifted(colour, noise(key, x, y, 8) + noise(key + "/brick", (x + 4 * (row % 2)) // 8, row, 10))

    return pattern(texel)


def snow_pattern(colour, key: str) -> list:
    def texel(x: int, y: int) -> tuple:
        if random_unit(key + "/blue", x, y) < 0.06:
            return mixed(colour, (170, 190, 230), 0.4)
        return shifted(colour, noise(key, x, y, 4))

    return pattern(texel)


# Ground cover: plant silhouettes over transparent texels, rooted in the
# bottom row.


def fill(image: list, mask: set, colour, key: str, amplitude: int) -> None:
    for x, y in mask:
        image[y][x] = opaque(shifted(colour, noise(key, x, y, amplitude)))


def blades_pattern(colour, key: str, count: int, shortest: int, tallest: int) -> list:
    """Grass blades leaning a little either way from the bottom row."""
    image = blank()
    for blade in range(count):
        root_x = 1 + int(random_unit(key, blade, 600) * (SIZE - 2))
        height = shortest + int(random_unit(key, blade, 601) * (tallest - shortest + 1))
        lean = int(random_unit(key, blade, 602) * 5) - 2
        mask = line_mask((root_x, SIZE - 1), (root_x + lean, SIZE - height), 0.5)
        fill(image, mask, shifted(colour, noise(key, blade, 603, 14)), f"{key}/{blade}", 8)
    return image


def flower_pattern(colour, key: str) -> list:
    """A green stem with two leaves and a head in the block's colour."""
    image = blank()
    stem = line_mask((7.5, SIZE - 1), (7.5, 6), 0.6)
    leaves = line_mask((7.5, 12), (4, 10), 0.6) | line_mask((7.5, 11), (11, 9), 0.6)
    fill(image, stem | leaves, STEM_GREEN, key + "/stem", 8)
    fill(image, disc_mask(7.5, 4.5, 2.6), colour, key + "/head", 14)
    fill(image, disc_mask(7.5, 4.5, 0.8), (240, 220, 120), key + "/centre", 6)
    return image


def dead_bush_pattern(colour, key: str) -> list:
    """Bare twigs fanning out from the root, each with a side twig."""
    image = blank()
    mask = set()
    for twig in range(5):
        top_x = 1 + twig * 3.3 + random_unit(key, twig, 610) * 1.5
        top_y = 2 + random_unit(key, twig, 611) * 6
        middle_x, middle_y = (7.5 + top_x) / 2, (SIZE - 1 + top_y) / 2
        mask |= line_mask((7.5, SIZE - 1), (top_x, top_y), 0.5)
        side = 2 if top_x >= 7.5 else -2
        mask |= line_mask((middle_x, middle_y), (middle_x + side, middle_y - 3), 0.5)
    fill(image, mask, colour, key, 12)
    return image


def reeds_pattern(colour, key: str) -> list:
    """Tall straight stalks, some with a brown head."""
    image = blank()
    for stalk in range(5):
        x = 1 + stalk * 3 + int(random_unit(key, stalk, 620) * 2)
        top = 1 + int(random_unit(key, stalk, 621) * 5)
        fill(image, line_mask((x, SIZE - 1), (x, top), 0.5), colour, f"{key}/{stalk}", 10)
        if stalk % 2 == 0:
            fill(image, rectangle_mask(x, top, x, top + 3) | rectangle_mask(x + 1, top + 1, x + 1, top + 2), REED_HEAD, f"{key}/head{stalk}", 8)
    return image


def cover_pattern(block_id: str, colour) -> list:
    words = block_id.split("_")
    if "flower" in words:
        return flower_pattern(colour, block_id)
    if "bush" in words:
        return dead_bush_pattern(colour, block_id)
    if "reeds" in words:
        return reeds_pattern(colour, block_id)
    if block_id == "tall_grass":
        return blades_pattern(colour, block_id, 9, 9, 15)
    return blades_pattern(colour, block_id, 8, 4, 8)


def torch_pattern(stick, flame, key: str) -> list:
    """A stick two texels wide from the bottom row up to row 6, where the
    post (POST_HEIGHT in block_shape.odin) ends, and a flame head above
    it on transparent texels."""
    image = blank()
    paint(image, rectangle_mask(7, 6, 8, SIZE - 1), stick, key + "/stick", 6)
    paint(image, disc_mask(7.5, 3.6, 2.4) | rectangle_mask(7, 0, 8, 2), flame, key + "/flame", 6)
    fill(image, disc_mask(7.5, 4, 1.1), (255, 244, 200), key + "/core", 4)
    return image


def block_family(block_id: str) -> str:
    """The material family, from the id."""
    words = block_id.split("_")
    if words[-1] == "ore" or block_id == "gold_quartz":
        return "ore"
    if block_id == "torch":
        return "torch"
    checks = [
        ("cover", "tuft" in words or "flower" in words or "bush" in words or "reeds" in words or block_id == "tall_grass"),
        ("log", "log" in words),
        ("leaves", "leaves" in words),
        ("water", "water" in words),
        ("grass", words[-1] == "grass"),
        ("dirt", "dirt" in words or block_id == "mud"),
        ("sand", "sand" in words),
        ("snow", "snow" in words),
        ("tar", "tar" in words or block_id == "asphalt"),
        ("concrete", "concrete" in words or block_id == "landing_pad"),
        ("brick", "brick" in words),
        ("stone", "stone" in words),
        ("rock", "rock" in words or "slag" in words),
    ]
    for family, matches in checks:
        if matches:
            return family
    return "default"


def face_pattern(family: str, colour, key: str, stone) -> list:
    """One face in the family's pattern and the face's colour."""
    if family == "ore":
        return ore_pattern(colour, key, stone)
    patterns = {
        "stone": stone_pattern,
        "rock": rock_pattern,
        "dirt": dirt_pattern,
        "grass": grass_top_pattern,
        "sand": lambda colour, key: noisy(colour, key, 6, 4),
        "log": bark_pattern,
        "leaves": leaves_pattern,
        "water": water_pattern,
        "snow": snow_pattern,
        "tar": tar_pattern,
        "concrete": concrete_pattern,
        "brick": brick_pattern,
        "default": lambda colour, key: noisy(colour, key, 8, 6),
    }
    return patterns[family](colour, key)


def block_files(block_id: str, faces: dict, stone) -> dict:
    """File suffix to image. faces maps top, side and bottom to colours."""
    family = block_family(block_id)
    if family == "cover":
        return {"": cover_pattern(block_id, faces["side"])}
    if family == "torch":
        files = {"": torch_pattern(faces["side"], faces["top"], block_id)}
        for group in ("top", "bottom"):
            files["_" + group] = face_pattern("default", faces[group], f"{block_id}/{group}", stone)
        return files
    if family == "grass":
        return {
            "": dirt_pattern(faces["bottom"], block_id),
            "_top": grass_top_pattern(faces["top"], block_id + "/top"),
            "_side": grass_side_pattern(faces["top"], faces["bottom"], block_id + "/side"),
        }
    if family == "log":
        return {
            "": bark_pattern(faces["side"], block_id),
            "_top": rings_pattern(faces["top"], faces["side"], block_id + "/top"),
            "_bottom": rings_pattern(faces["bottom"], faces["side"], block_id + "/bottom"),
        }
    files = {"": face_pattern(family, faces["side"], block_id, stone)}
    for group in ("top", "bottom"):
        if faces[group] != faces["side"]:
            files["_" + group] = face_pattern(family, faces[group], f"{block_id}/{group}", stone)
    return files


# Item shapes: a mask of texels, drawn with a lit top left edge, a shaded
# bottom right edge and a dark outline around it.


def disc_mask(centre_x: float, centre_y: float, radius: float) -> set:
    return {(x, y) for y in range(SIZE) for x in range(SIZE) if math.hypot(x - centre_x, y - centre_y) <= radius}


def rectangle_mask(left: int, top: int, right: int, bottom: int) -> set:
    """Inclusive corners."""
    return {(x, y) for y in range(top, bottom + 1) for x in range(left, right + 1)}


def rounded_rectangle_mask(left: int, top: int, right: int, bottom: int) -> set:
    return rectangle_mask(left, top, right, bottom) - {(left, top), (right, top), (left, bottom), (right, bottom)}


def line_mask(start: tuple, finish: tuple, half_width: float) -> set:
    """Texels within half_width of the segment."""
    (start_x, start_y), (finish_x, finish_y) = start, finish
    length_squared = (finish_x - start_x) ** 2 + (finish_y - start_y) ** 2
    mask = set()
    for y in range(SIZE):
        for x in range(SIZE):
            along = max(0.0, min(1.0, ((x - start_x) * (finish_x - start_x) + (y - start_y) * (finish_y - start_y)) / length_squared))
            closest_x, closest_y = start_x + along * (finish_x - start_x), start_y + along * (finish_y - start_y)
            if math.hypot(x - closest_x, y - closest_y) <= half_width:
                mask.add((x, y))
    return mask


def lump_mask(key: str, centre_x: float, centre_y: float, radius: float) -> set:
    """A disc whose radius wobbles with the angle."""
    bumps = [0.75 + 0.35 * random_unit(key, index, 500) for index in range(8)]
    mask = set()
    for y in range(SIZE):
        for x in range(SIZE):
            angle = math.atan2(y - centre_y, x - centre_x) % (2 * math.pi)
            position = angle / (2 * math.pi) * 8
            index = int(position)
            weight = position - index
            wobble = bumps[index] * (1 - weight) + bumps[(index + 1) % 8] * weight
            if math.hypot(x - centre_x, y - centre_y) <= radius * wobble:
                mask.add((x, y))
    return mask


def paint(image: list, mask: set, colour, key: str, texture: int = 6) -> None:
    """Fills the mask in colour with a little noise, lights its top left
    edge, shades its bottom right edge and outlines it."""
    for x, y in mask:
        amount = noise(key, x, y, texture)
        if (x - 1, y) not in mask or (x, y - 1) not in mask:
            amount += 34
        elif (x + 1, y) not in mask or (x, y + 1) not in mask:
            amount -= 34
        image[y][x] = opaque(shifted(colour, amount))
    outline = opaque(scaled(colour, 0.3))
    for x, y in mask:
        for neighbour_x, neighbour_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            inside = 0 <= neighbour_x < SIZE and 0 <= neighbour_y < SIZE
            if inside and (neighbour_x, neighbour_y) not in mask and image[neighbour_y][neighbour_x] == TRANSPARENT:
                image[neighbour_y][neighbour_x] = outline


def draw_plate(colour, key: str) -> list:
    image = blank()
    paint(image, rounded_rectangle_mask(2, 4, 13, 11), colour, key, 4)
    return image


def draw_bar(colour, key: str) -> list:
    """An ingot: a bar narrower at the top."""
    image = blank()
    mask = rectangle_mask(2, 7, 13, 11) | rectangle_mask(4, 5, 11, 6)
    paint(image, mask, colour, key, 4)
    return image


def draw_lump(colour, key: str, radius: float = 5.5) -> list:
    image = blank()
    paint(image, lump_mask(key, 7.5, 8.5, radius), colour, key, 16)
    return image


def draw_low_grade_lump(colour, key: str) -> list:
    """Duller and smaller than the ore, with rock showing."""
    return draw_lump(mixed(colour, (110, 104, 96), 0.5), key, 4.5)


def draw_crushed(colour, key: str) -> list:
    """A little pile of grains."""
    image = blank()
    for index, (centre_x, centre_y) in enumerate(((5, 10), (10.5, 10), (7.5, 5.5))):
        paint(image, lump_mask(f"{key}/{index}", centre_x, centre_y, 3.2), colour, f"{key}/{index}", 12)
    return image


def draw_gear(colour, key: str) -> list:
    image = blank()
    mask = set()
    for y in range(SIZE):
        for x in range(SIZE):
            distance = math.hypot(x - 7.5, y - 7.5)
            angle = math.atan2(y - 7.5, x - 7.5)
            tooth = math.cos(8 * angle) > 0.2
            if 2.5 < distance <= (7.5 if tooth else 5.6):
                mask.add((x, y))
    paint(image, mask, colour, key, 4)
    return image


def draw_rod(colour, key: str, half_width: float) -> list:
    image = blank()
    paint(image, line_mask((3, 12), (12, 3), half_width), colour, key, 3)
    return image


def draw_pipe(colour, key: str) -> list:
    image = blank()
    paint(image, rectangle_mask(2, 6, 13, 9), colour, key, 3)
    paint(image, rectangle_mask(1, 5, 2, 10) | rectangle_mask(13, 5, 14, 10), scaled(colour, 0.8), key + "/flange", 3)
    return image


def draw_circuit(key: str) -> list:
    image = blank()
    paint(image, rectangle_mask(2, 3, 13, 12), CIRCUIT_BOARD, key, 4)
    for x, y in rectangle_mask(4, 5, 11, 5) | rectangle_mask(4, 10, 11, 10) | rectangle_mask(4, 5, 4, 10):
        image[y][x] = opaque(CIRCUIT_TRACE)
    for x, y in rectangle_mask(7, 7, 10, 8):
        image[y][x] = opaque((30, 30, 34))
    return image


def draw_flask(colour, key: str) -> list:
    """A round bottomed flask of glass filled with colour."""
    image = blank()
    glass = MATERIAL_COLOURS["glass"]
    paint(image, rectangle_mask(6, 1, 9, 6) | disc_mask(7.5, 10, 4.8), glass, key + "/glass", 2)
    for x, y in disc_mask(7.5, 10.5, 3.6):
        if y >= 9:
            image[y][x] = opaque(shifted(colour, noise(key, x, y, 6)))
    return image


def draw_pickaxe(colour, key: str) -> list:
    """An upright handle under a crescent head whose tips hang down."""
    image = blank()
    paint(image, rectangle_mask(7, 4, 8, 14), MATERIAL_COLOURS["wood"], key + "/handle", 4)
    head = {(x, y) for x, y in disc_mask(7.5, 10, 7.4) if math.hypot(x - 7.5, y - 10) > 4.6 and y <= 7}
    paint(image, head, colour, key + "/head", 4)
    return image


def draw_hammer(colour, key: str) -> list:
    """An upright handle, the head across its top reaching to the right."""
    image = blank()
    paint(image, rectangle_mask(5, 5, 6, 14), MATERIAL_COLOURS["wood"], key + "/handle", 4)
    paint(image, rounded_rectangle_mask(3, 1, 13, 4), colour, key + "/head", 4)
    return image


def draw_magnet(key: str) -> list:
    """A horseshoe magnet with grey tips."""
    image = blank()
    arc = {(x, y) for x, y in disc_mask(7.5, 6.5, 5.5) if math.hypot(x - 7.5, y - 6.5) > 2.6 and y <= 6.5}
    legs = rectangle_mask(2, 7, 4, 10) | rectangle_mask(11, 7, 13, 10)
    paint(image, arc | legs, MAGNET_RED, key, 4)
    paint(image, rectangle_mask(2, 11, 4, 13) | rectangle_mask(11, 11, 13, 13), MATERIAL_COLOURS["iron"], key + "/tips", 3)
    return image


def draw_charge(key: str) -> list:
    """A charge: a red cylinder with a fuse."""
    image = blank()
    paint(image, rectangle_mask(4, 5, 11, 14), CHARGE_RED, key, 4)
    paint(image, line_mask((8, 4), (11, 1), 0.6), FUSE, key + "/fuse", 2)
    return image


def draw_schematic(key: str) -> list:
    """A sheet with drawn lines."""
    image = blank()
    paint(image, rectangle_mask(3, 1, 12, 14), PAPER, key, 2)
    for y in (4, 7, 10):
        for x in range(5, 11 if y != 10 else 9):
            image[y][x] = opaque(PAPER_LINE)
    return image


def draw_sapling(key: str) -> list:
    image = blank()
    paint(image, rectangle_mask(7, 7, 8, 14), MATERIAL_COLOURS["wood"], key + "/stem", 3)
    paint(image, lump_mask(key + "/left", 4.5, 6, 3), SAPLING_GREEN, key + "/left", 8)
    paint(image, lump_mask(key + "/right", 11, 4.5, 3.2), SAPLING_GREEN, key + "/right", 8)
    return image


def draw_machine(colour, key: str) -> list:
    """A box with a darker base and a lit panel."""
    image = blank()
    paint(image, rectangle_mask(2, 3, 13, 11), colour, key, 4)
    paint(image, rectangle_mask(1, 12, 14, 14), scaled(colour, 0.55), key + "/base", 3)
    for x, y in rectangle_mask(5, 5, 10, 8):
        image[y][x] = opaque(scaled(colour, 0.75))
    return image


def draw_tool(item_id: str, colour, key: str) -> list:
    words = item_id.split("_")
    if "pickaxe" in words:
        return draw_pickaxe(colour, key)
    if "hammer" in words:
        return draw_hammer(colour, key)
    if item_id == "magnetometer":
        return draw_magnet(key)
    if "charge" in words:
        return draw_charge(key)
    if "schematic" in words:
        return draw_schematic(key)
    return draw_pickaxe(colour, key)


def draw_intermediate(item_id: str, colour, key: str) -> list:
    words = item_id.split("_")
    if "crushed" in words:
        return draw_crushed(colour, key)
    if "plate" in words:
        return draw_plate(colour, key)
    if "gear" in words:
        return draw_gear(colour, key)
    if "rod" in words or "stick" in words:
        return draw_rod(colour, key, 1.2)
    if "wire" in words:
        return draw_rod(colour, key, 0.6)
    if "pipe" in words:
        return draw_pipe(colour, key)
    if "circuit" in words:
        return draw_circuit(key)
    if "pack" in words:
        return draw_flask(colour, key)
    if "charcoal" in words or "sulfur" in words:
        return draw_lump(colour, key)
    return draw_bar(colour, key)


def draw_raw(item_id: str, colour, key: str) -> list:
    if item_id == "sapling":
        return draw_sapling(key)
    if item_id.endswith("_low_grade"):
        return draw_low_grade_lump(colour, key)
    return draw_lump(colour, key)


# UI icons.

UI_ICON_NAMES = [
    "button_south",
    "button_east",
    "button_west",
    "button_north",
    "bumper_left",
    "bumper_right",
    "trigger_left",
    "trigger_right",
    "stick_left",
    "stick_right",
    "dpad",
    "menu",
    "view",
    "key",
    "category_raw",
    "category_intermediate",
    "category_tool",
    "category_machine",
    "category_block",
    "category_logistics",
    "category_power",
    "category_science",
    "mission_control",
    "journal",
    "map",
    "settings",
    "search",
    "inventory",
    "recipes",
    "technologies",
]

UI_FACE = (58, 62, 78)
UI_RIM = (184, 190, 208)
UI_LIGHT = (235, 235, 240)
UI_DARK = (30, 32, 40)
UI_ACCENT = (236, 176, 64)
UI_BLUE = (90, 160, 230)
UI_RED = (200, 70, 56)

# 3 by 5 pixel letters, rows top to bottom.
PIXEL_LETTERS = {
    "L": ["X..", "X..", "X..", "X..", "XXX"],
    "R": ["XX.", "X.X", "XX.", "X.X", "X.X"],
    "T": ["XXX", ".X.", ".X.", ".X.", ".X."],
    "1": [".X.", "XX.", ".X.", ".X.", "XXX"],
}

FACE_BUTTON_CENTRES = {
    "north": (7.5, 3),
    "south": (7.5, 12),
    "west": (3, 7.5),
    "east": (12, 7.5),
}


def stamp_letter(image: list, letter: str, left: int, top: int, colour) -> None:
    for row, line in enumerate(PIXEL_LETTERS[letter]):
        for column, cell in enumerate(line):
            if cell == "X":
                image[top + row][left + column] = opaque(colour)


def stamp_label(image: list, label: str, left: int, top: int, colour) -> None:
    """Letters side by side, one texel apart."""
    for index, letter in enumerate(label):
        stamp_letter(image, letter, left + index * 4, top, colour)


def draw_face_button(lit: str, key: str) -> list:
    """Four buttons in a diamond, the named one lit."""
    image = blank()
    for position, (centre_x, centre_y) in FACE_BUTTON_CENTRES.items():
        colour = UI_ACCENT if position == lit else UI_FACE
        paint(image, disc_mask(centre_x, centre_y, 2.6), colour, f"{key}/{position}", 2)
    return image


def draw_bumper(letter: str, key: str) -> list:
    image = blank()
    mask = rounded_rectangle_mask(1, 4, 14, 11)
    paint(image, mask, UI_RIM, key, 2)
    stamp_label(image, letter + "1", 4, 5, UI_DARK)
    return image


def draw_trigger(letter: str, key: str) -> list:
    """A tall trigger, rounded at the top."""
    image = blank()
    mask = {(x, y) for x, y in rectangle_mask(3, 3, 12, 14)} | {(x, y) for x, y in disc_mask(7.5, 4.5, 4.6) if y <= 4}
    paint(image, mask, UI_RIM, key, 2)
    stamp_label(image, letter + "T", 4, 7, UI_DARK)
    return image


def draw_stick(letter: str, key: str) -> list:
    """A stick seen from above: a rim and a cap with the letter."""
    image = blank()
    paint(image, disc_mask(7.5, 7.5, 7.2), UI_FACE, key + "/rim", 2)
    paint(image, disc_mask(7.5, 7.5, 4.6), UI_RIM, key + "/cap", 2)
    stamp_letter(image, letter, 6, 5, UI_DARK)
    return image


def draw_dpad(key: str) -> list:
    image = blank()
    paint(image, rectangle_mask(6, 1, 9, 14) | rectangle_mask(1, 6, 14, 9), UI_RIM, key, 2)
    for x, y in rectangle_mask(7, 7, 8, 8):
        image[y][x] = opaque(UI_FACE)
    return image


def draw_menu_button(key: str) -> list:
    """Three lines on a round button."""
    image = blank()
    paint(image, disc_mask(7.5, 7.5, 7.2), UI_FACE, key, 2)
    for y in (5, 8, 11):
        for x in range(4, 12):
            image[y][x] = opaque(UI_LIGHT)
    return image


def draw_view_button(key: str) -> list:
    """Two overlapping windows on a round button."""
    image = blank()
    paint(image, disc_mask(7.5, 7.5, 7.2), UI_FACE, key, 2)
    for x, y in rectangle_mask(3, 4, 9, 9) - rectangle_mask(4, 5, 8, 8):
        image[y][x] = opaque(UI_LIGHT)
    for x, y in rectangle_mask(6, 7, 12, 12):
        image[y][x] = opaque(UI_LIGHT)
    return image


def draw_key_cap(key: str) -> list:
    """A blank dark key cap, lit at the top left; stretched for long names."""
    image = blank()
    paint(image, rounded_rectangle_mask(0, 0, 15, 15), UI_FACE, key, 0)
    return image


def draw_cube(colour, key: str) -> list:
    image = blank()
    paint(image, rectangle_mask(2, 2, 13, 13), colour, key, 10)
    return image


def draw_belt(key: str) -> list:
    """A belt with chevrons."""
    image = blank()
    paint(image, rounded_rectangle_mask(0, 4, 15, 11), UI_FACE, key, 2)
    for left in (2, 7, 12):
        for step in range(3):
            for x, y in ((left + step, 5 + step), (left + step, 10 - step)):
                if x < SIZE:
                    image[y][x] = opaque(UI_ACCENT)
    return image


def draw_bolt(key: str) -> list:
    image = blank()
    mask = line_mask((10, 1), (5, 8), 1.3) | line_mask((5, 8), (10, 8), 1.1) | line_mask((10, 8), (5, 14), 1.3)
    paint(image, mask, UI_ACCENT, key, 2)
    return image


def draw_mission_control(key: str) -> list:
    """A mast with a dish and two signal arcs."""
    image = blank()
    paint(image, rectangle_mask(7, 7, 8, 14) | rectangle_mask(4, 13, 11, 14), UI_RIM, key + "/mast", 2)
    paint(image, disc_mask(7.5, 6, 2), UI_ACCENT, key + "/dish", 2)
    for radius in (4.2, 6.6):
        for x, y in disc_mask(7.5, 6, radius + 0.5):
            if math.hypot(x - 7.5, y - 6) > radius - 0.5 and y <= 4 and image[y][x] == TRANSPARENT:
                image[y][x] = opaque(UI_LIGHT)
    return image


def draw_book(key: str) -> list:
    image = blank()
    paint(image, rectangle_mask(3, 1, 12, 14), UI_RED, key + "/cover", 3)
    for y in range(3, 13):
        image[y][11] = opaque(PAPER)
    for x, y in rectangle_mask(5, 4, 9, 5):
        image[y][x] = opaque(UI_ACCENT)
    return image


def draw_folded_map(key: str) -> list:
    image = blank()
    for index, (left, right) in enumerate(((1, 5), (6, 10), (11, 14))):
        paint(image, rectangle_mask(left, 3, right, 12), scaled(PAPER, 0.85 if index % 2 else 1.0), f"{key}/{index}", 3)
    paint(image, disc_mask(8, 7, 1.6), UI_RED, key + "/pin", 2)
    return image


def draw_magnifier(key: str) -> list:
    image = blank()
    ring = {(x, y) for x, y in disc_mask(6, 6, 4.8) if math.hypot(x - 6, y - 6) > 3}
    paint(image, ring | line_mask((9.5, 9.5), (13.5, 13.5), 1.2), UI_RIM, key, 2)
    return image


def draw_chest(key: str) -> list:
    image = blank()
    wood = MATERIAL_COLOURS["wood"]
    paint(image, rectangle_mask(1, 4, 14, 13), wood, key + "/box", 6)
    for x in range(1, 15):
        image[7][x] = opaque(scaled(wood, 0.5))
    paint(image, rectangle_mask(6, 6, 9, 9), MATERIAL_COLOURS["iron"], key + "/latch", 2)
    return image


def draw_research_tree(key: str) -> list:
    """Three nodes joined: a root below two branches."""
    image = blank()
    paint(image, line_mask((7.5, 11), (3.5, 4), 0.7) | line_mask((7.5, 11), (11.5, 4), 0.7), UI_RIM, key + "/lines", 2)
    for index, (centre_x, centre_y) in enumerate(((7.5, 11.5), (3.5, 3.5), (11.5, 3.5))):
        paint(image, disc_mask(centre_x, centre_y, 2.4), UI_BLUE if index else UI_ACCENT, f"{key}/{index}", 2)
    return image


def ui_icon_image(name: str) -> list:
    if name.startswith("button_"):
        return draw_face_button(name.removeprefix("button_"), name)
    side = "L" if name.endswith("_left") else "R"
    if name.startswith("bumper_"):
        return draw_bumper(side, name)
    if name.startswith("trigger_"):
        return draw_trigger(side, name)
    if name.startswith("stick_"):
        return draw_stick(side, name)
    pictures = {
        "dpad": lambda: draw_dpad(name),
        "menu": lambda: draw_menu_button(name),
        "view": lambda: draw_view_button(name),
        "key": lambda: draw_key_cap(name),
        "category_raw": lambda: draw_lump(MATERIAL_COLOURS["copper"], name),
        "category_intermediate": lambda: draw_gear(MATERIAL_COLOURS["iron"], name),
        "category_tool": lambda: draw_pickaxe(MATERIAL_COLOURS["iron"], name),
        "category_machine": lambda: draw_machine((120, 130, 150), name),
        "category_block": lambda: draw_cube(MATERIAL_COLOURS["stone"], name),
        "category_logistics": lambda: draw_belt(name),
        "category_power": lambda: draw_bolt(name),
        "category_science": lambda: draw_flask(UI_BLUE, name),
        "mission_control": lambda: draw_mission_control(name),
        "journal": lambda: draw_book(name),
        "map": lambda: draw_folded_map(name),
        "settings": lambda: draw_gear(UI_RIM, name),
        "search": lambda: draw_magnifier(name),
        "inventory": lambda: draw_chest(name),
        "recipes": lambda: draw_schematic(name),
        "technologies": lambda: draw_research_tree(name),
    }
    return pictures[name]()


def item_image(item: dict, block_images: dict) -> list:
    """block_images maps a block id to its plain texture."""
    item_id = item["id"]
    if item.get("places_block") in block_images:
        return block_images[item["places_block"]]
    colour = material_colour(item_id) or hash_colour(item_id)
    category = item.get("category", "")
    if category == "intermediate":
        return draw_intermediate(item_id, colour, item_id)
    if category == "tool":
        return draw_tool(item_id, colour, item_id)
    if category == "machine":
        return draw_machine(colour, item_id)
    return draw_raw(item_id, colour, item_id)


# Data.


def read_blocks() -> dict:
    """Block id to {top, side, bottom} colours, in file order."""
    text = (DATA_DIRECTORY / "blocks.sjson").read_text()
    ids = [(match.start(), match.group(1)) for match in BLOCK_ID_PATTERN.finditer(text)]
    blocks = {}
    for index, (start, block_id) in enumerate(ids):
        end = ids[index + 1][0] if index + 1 < len(ids) else len(text)
        texture = BLOCK_TEXTURE_PATTERN.search(text, start, end)
        if texture is None:
            raise SystemExit(f"blocks.sjson: {block_id} has no texture line")
        channels = [int(value) for value in texture.groups()]
        blocks[block_id] = {"top": tuple(channels[0:3]), "side": tuple(channels[3:6]), "bottom": tuple(channels[6:9])}
    return blocks


def read_items() -> list:
    text = (DATA_DIRECTORY / "items.sjson").read_text()
    items = []
    for match in ITEM_LINE_PATTERN.finditer(text):
        item = {"id": match.group(1)}
        item.update(dict(ITEM_FIELD_PATTERN.findall(match.group(2))))
        items.append(item)
    return items


def write_image(directory: pathlib.Path, name: str, image: list) -> None:
    path = directory / f"{name}.png"
    path.write_bytes(encode_png(image))
    print(f"wrote {path.relative_to(REPOSITORY_ROOT)}")


def main() -> None:
    BLOCK_TEXTURES_DIRECTORY.mkdir(parents=True, exist_ok=True)
    ITEM_TEXTURES_DIRECTORY.mkdir(parents=True, exist_ok=True)
    blocks = read_blocks()
    stone = blocks.get("stone", {}).get("side", FALLBACK_STONE)
    block_images = {}
    for block_id, faces in blocks.items():
        if block_id == "air":
            continue
        for suffix, image in block_files(block_id, faces, stone).items():
            write_image(BLOCK_TEXTURES_DIRECTORY, block_id + suffix, image)
            if suffix == "":
                block_images[block_id] = image
    for item in read_items():
        write_image(ITEM_TEXTURES_DIRECTORY, item["id"], item_image(item, block_images))
    UI_ICONS_DIRECTORY.mkdir(parents=True, exist_ok=True)
    for name in UI_ICON_NAMES:
        write_image(UI_ICONS_DIRECTORY, name, ui_icon_image(name))


if __name__ == "__main__":
    main()
