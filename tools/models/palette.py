"""The materials of the OBJ machine models (work item 0204): DESIGN.md's
palette (Art direction), desaturated for daylight.

MATERIALS maps a material name to its sRGB bytes and whether it glows.
The game reads Kd as display bytes without gamma (doc/presentation.md,
Machine models), so kit.material writes bytes / 255 straight into Base
Color. Only the materials a machine uses are written to its .mtl.

Work item 0205 added timber, timber_dark and stone for the hand built
pieces (the wooden chest, the schematic crate, the small pole, the stone
cutting table and the stone cutter), which the steel palette has no
colour for, and lamp_glow, the warm white of a lamp's head.
"""

MATERIALS = {
    "steel": ((74, 84, 99), False),
    "steel_dark": ((52, 58, 68), False),
    "galvanised": ((150, 156, 160), False),
    "soot": ((40, 38, 37), False),
    "hazard_black": ((34, 34, 36), False),
    "mining_ochre": ((176, 132, 52), False),
    "smelting_brick": ((140, 66, 48), False),
    "power_yellow": ((206, 168, 46), False),
    "fluids_teal": ((54, 128, 124), False),
    "logistics_grey": ((118, 120, 122), False),
    "science_white": ((208, 212, 214), False),
    "heat_glow": ((255, 140, 48), True),
    "electric_glow": ((80, 220, 240), True),
    "timber": ((122, 88, 56), False),
    "timber_dark": ((82, 58, 38), False),
    "stone": ((128, 126, 120), False),
    "lamp_glow": ((255, 236, 190), True),
}
