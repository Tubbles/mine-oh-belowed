# 0183: The command socket on the field world

Status: todo (M13 follow up, from the switch of 0179; whenever the assistant needs it)

## Goal

The assistant drives a field session through the command socket (`doc/commands.md`) as it drove the block world: where the player stands and looks, moving and turning them, the veins on the sphere, the entities with their frame cells, placing on a frame. Today `query player` reads the block player's fields, `teleport` takes block coordinates, `query veins` and `vein` read the block world's registry, and the commands that read `World.chunks` answer about an empty block world. A headless screenshot of a field session therefore shows the spawn's view only (2026-10-03, the pod and the outcrops never framed).

## Change

- `query player` answers the field player: feet as a world position and as latitude, longitude and height, yaw, pitch, the held tool and hotbar slot; `teleport <x> <y> <z>` takes a world position in metres and `teleport <latitude> <longitude>` a surface point; a new `look <yaw> <pitch>` sets the field player's look (a frame side write through the input record, as the other commands go).
- `query veins` lists the sphere veins (direction as latitude and longitude, radius, reservoir); `vein` adds one on the sphere at a surface point; `query entities` prints the frame and cell; `place` takes a frame and cell.
- Commands that only mean something on the block world answer `error no block world` instead of an empty answer.
- `doc/commands.md` updated per command.

## Verify

- The build and check commands of 0168; the socket's tests per changed command.
- A headless run: start a new world under `xvfb-run` with `--dev`, `look` at the pod and `screenshot`; the PNG shows the pod and an outcrop.
