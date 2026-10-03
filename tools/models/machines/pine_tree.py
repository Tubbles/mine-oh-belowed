"""The pine (work item 0197, doc/content.md, Trees): a tree's model, a
machine record of kind tree that the planet's generation places, never
an item. Its trunk is the species' in data/planets.sjson in cells of
the pitch of data/game.sjson, so the trunk the walk and the aim meet is
the trunk drawn; three stacked crowns turned unevenly so their edges do
not line up. The model's bottom is the trunk's base, sunk under the
ground. Blender frame of kit.py: x the front, y = -game z, z up."""

import pathlib

import sjson

from .. import kit

DATA_DIRECTORY = pathlib.Path(__file__).resolve().parents[3] / "data"


def tree_species(machine_id):
    """The first species of any planet whose machine is machine_id."""
    for planet in sjson.load(DATA_DIRECTORY / "planets.sjson")["planets"]:
        for species in planet["trees"]["species"]:
            if species["machine"] == machine_id:
                return species
    raise SystemExit(f"model of {machine_id}: no tree species in data/planets.sjson names it")


def pitch_millimetres():
    return sjson.load(DATA_DIRECTORY / "game.sjson")["foundation_pitch_millimetres"]


def build(machine):
    """machine: its record (tools/models/records.py); the trunk comes from
    its species."""
    trunk_radius = tree_species(machine.id)["trunk_radius_millimetres"] / pitch_millimetres()
    volumes = [
        # The trunk from the sunk base up into the crown.
        kit.cylinder((0.0, 0.0), 0.0, 12.0, trunk_radius, 7, "bark"),
        # The lower crown, its bottom 2.5 m over the ground, over the
        # player's head.
        kit.cone((0.0, 0.0), 5.6, 11.0, 2.6, 0.8, 9, "needles_dark", rotation=0.0),
        kit.cone((0.0, 0.0), 9.0, 13.4, 2.0, 0.5, 9, "needles", rotation=0.35),
        kit.cone((0.0, 0.0), 12.0, 15.0, 1.2, 0.0, 7, "needles_light", rotation=0.8),
    ]
    kit.join(volumes, "body")
