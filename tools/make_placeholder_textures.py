#!/usr/bin/env python3
"""Write the placeholder block textures and item icons (work item 0060) to
data/textures/blocks/ and data/textures/items/.

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
material family taken from the id: noise per family, ore speckles in the
ore's colour over stone, bark grain and a ring top for logs, mottled
leaves, a grass top over a dirt side, bricks and mortar. Ground cover
(work item 0082: tufts, tall grass, flowers, dead bushes, reeds) is a
plant silhouette on transparent texels, drawn on the cross quads.

Items: by category, coloured from a table of the common materials (a word
of the id picks it) or a colour hashed from the id: plates as rounded
rectangles, ores as lumps, gears as toothed rings, tools as simple
silhouettes, machines as a box with a darker base, science packs as a
flask. An item that places a block shows the block's plain texture.

The whole set is a placeholder: hand made art replaces the files later.
"""

import math
import pathlib
import re
import struct
import zlib

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA_DIRECTORY = REPOSITORY_ROOT / "data"
BLOCK_TEXTURES_DIRECTORY = DATA_DIRECTORY / "textures" / "blocks"
ITEM_TEXTURES_DIRECTORY = DATA_DIRECTORY / "textures" / "items"
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
    return shifted(colour, noise(key, x, y, 10) + smooth_noise(key, x, y, 4, 14))


def stone_pattern(colour, key: str) -> list:
    return pattern(lambda x, y: stone_texel(colour, key, x, y))


def rock_pattern(colour, key: str) -> list:
    """Stone with horizontal strata."""
    return pattern(lambda x, y: shifted(stone_texel(colour, key, x, y), -12 if (y + x // 6) % 5 == 0 else 0))


def ore_pattern(colour, key: str, stone) -> list:
    """Clusters of ore colour over stone."""
    image = stone_pattern(stone, key + "/stone")
    for cluster in range(6):
        centre_x = int(random_unit(key, cluster, 100) * SIZE)
        centre_y = int(random_unit(key, cluster, 101) * SIZE)
        for step in range(4):
            x = (centre_x + int(random_unit(key, cluster, 200 + step) * 3) - 1) % SIZE
            y = (centre_y + int(random_unit(key, cluster, 300 + step) * 3) - 1) % SIZE
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
        return shifted(colour, amount + smooth_noise(key, x, y, 4, 8))

    return pattern(texel)


def water_pattern(colour, key: str) -> list:
    def texel(x: int, y: int) -> tuple:
        wave = math.sin((x + 2 * y) * 2 * math.pi / SIZE + smooth_noise(key, x, y, 8, 3))
        return shifted(colour, int(wave * 8) + noise(key, x, y, 3))

    return pattern(texel)


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


def block_family(block_id: str) -> str:
    """The material family, from the id."""
    words = block_id.split("_")
    if words[-1] == "ore" or block_id == "gold_quartz":
        return "ore"
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
    image = blank()
    paint(image, line_mask((4, 13), (11, 5), 0.9), MATERIAL_COLOURS["wood"], key + "/handle", 4)
    head = {(x, y) for x, y in disc_mask(8.5, 8.5, 7.4) if math.hypot(x - 8.5, y - 8.5) > 4.6 and x + y <= 12 and x - y > -9 and y - x > -9}
    paint(image, head, colour, key + "/head", 4)
    return image


def draw_hammer(colour, key: str) -> list:
    image = blank()
    paint(image, line_mask((4, 13), (10, 5), 0.9), MATERIAL_COLOURS["wood"], key + "/handle", 4)
    paint(image, line_mask((6, 2), (13, 7), 1.6), colour, key + "/head", 4)
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


if __name__ == "__main__":
    main()
