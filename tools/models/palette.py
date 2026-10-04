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
    # Trees (0197): the bark and three greens of a pine's crown, from the
    # shade underneath to the light top.
    "bark": ((86, 62, 44), False),
    "needles_dark": ((38, 70, 46), False),
    "needles": ((50, 88, 56), False),
    "needles_light": ((70, 108, 66), False),
    # The stone furnace: rubble stone, its dark joints, rusted iron, the
    # rust brown of the hood and the pipes, the dirty white console and
    # a green signal light.
    "furnace_stone": ((128, 96, 78), False),
    "furnace_mortar": ((54, 42, 38), False),
    "furnace_iron": ((90, 70, 62), False),
    "furnace_rust": ((126, 86, 66), False),
    "console_white": ((196, 190, 180), False),
    "signal_glow": ((110, 240, 120), True),
    # 0221, the pod and its airlock door (made in the pod lab): a dark
    # cabin. Near black for the lining and recesses (and the heat
    # shield and scorch outside), charcoal for panels and cabinets, a mid
    # grey worn metal for the hull outside and the edges that catch the
    # light inside, dark brown padding, orange for the accents (hazard
    # stripes, handles, harness, rims), and three glows: warm amber for
    # the lamps and screens (the dominant light), green screens and a
    # cold white for a few screens and strips.
    "pod_black": ((26, 25, 24), False),
    "pod_dark": ((46, 46, 48), False),
    "pod_metal": ((124, 122, 114), False),
    "pod_padding": ((92, 70, 50), False),
    "pod_orange": ((204, 98, 28), False),
    "pod_glow_amber": ((255, 150, 40), True),
    "pod_glow_green": ((110, 236, 140), True),
    "pod_glow_white": ((196, 228, 255), True),
}
