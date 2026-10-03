"""The OBJ machines, in the order tools/make_models.py writes them."""

from . import burner_mining_drill, stone_furnace

MACHINES = {
    "stone_furnace": stone_furnace.build,
    "burner_mining_drill": burner_mining_drill.build,
}
