# The stone furnace: modelling brief

You are the modeller of one machine for a factory building game set on an alien planet: the stone furnace, the first machine the player builds. This directory is your whole world. Everything you need is in it, and nothing outside it may be read or run: not the repository around it, not its docs, not git, not the web. If something is missing, say so in your report instead of looking for it elsewhere.

## What the furnace is

A stone furnace that smelts ore with wood and coal, early in the game's technology. The client's words on how every machine of this game looks: "Astro-industrial punk, combining 1) clean spacey panels, LEDs, LCDs, bright blinking colors, intriguing buttons and levers, with 2) rough, hard, dirty materials and grime, pipes, bolts, glass, metal, stone, brown, dark muted colors and gray. Almost like a juxtaposition." The two worlds are interleaved all over a machine, never split into an industrial lower half under a clean upper half. The ratio changes over the game, and the stone furnace sits at the rough end: about 80 rough to 20 clean, roughly a stone and iron furnace with one small console bolted on. Everything is dirty and used; the clean parts read clean by shape, light and colour, not by being spotless. The machine is automated: no door, no room for a person inside. The client wants it "larger, feeling awe-inspiring, formidable, and intimidating through sheer presence, more akin to Satisfactory style machine sizes": the player, 1.8 m tall, stands beside it and feels small.

## The reference images (`reference/`)

Look at every one of them with the Read tool before you start, at full size, and keep going back to them. The client approved these pictures; the model should read as the thing in them.

- `hero_three_quarter.png`: the canonical view, a three quarter from the front left with an astronaut for scale. The firebox mouth is on the front, the console on the left face.
- `turnaround.png`: four orthographic elevations on one ground line: front (the mouth), left (the console), back (the pipes), right (a small panel).
- `plan.png`: the roof plan from above.
- `rear_quarter.png`: the back and the right side with the astronaut.
- `detail_mouth.png`, `detail_top.png`: the firebox mouth and the chimney top up close.
- `sheet_all_views.png`: all of the above on one sheet.

## Size, frame and limits

- The footprint is 10 by 10 by 12 cells of 0.5 m: 5 m wide, 5 m deep, 6 m high. The client chose it from the images. Build in Blender's frame as `tools/models/kit.py` documents: one unit per cell, the footprint spanning x and y from -5 to 5 and z from 0 to 12, the front (the mouth) at +X, the left face (the console) at -Y.
- Nothing may leave the footprint sideways (x and y within -5.02 to 5.02) or go below the ground (z at least -0.02). A chimney or a pipe may rise above z 12.
- The player walks on the ground around the machine. A column of cells your model leaves empty from the ground up is a place the player can stand; tell me in the report which cells those are, in cell coordinates, if you leave any.
- The body is one mesh object named `body` with at most 3200 triangles. The furnace has no moving part, so there is no `part` object. The exporter triangulates and applies modifiers.
- At most 8 materials on the body. The game draws every triangle flat shaded: its material's colour (`Kd`) times a shade of the triangle's normal. There are no textures, no vertex colours, no smooth shading: a surface's character has to be geometry. A material with a non zero emission colour (`Ke`) is drawn unshaded at full colour and pulses while the furnace works: use it for the fire, the screens and the lights.
- The player sees the machine from 2 m and from 30 m, in daylight and by its own glow at night, from every side and from above when standing on it.

## Tools

- `tools/models/kit.py`: the helper functions the game's models are built with (boxes, cylinders, cones, frustums, wedges, rings, pipes with bent corners, plates on a face, strips, hatches, rib rows, boolean cuts and openings, a seeded random, `join` to merge volumes into one object). Read its docstrings. You may use them, change them or add to them, and you may use any Blender operator, bmesh code or modifier (booleans, bevel, array, solidify, displacement, loop cuts) as you see fit: the exporter writes plain triangles whatever made them.
- `tools/models/palette.py`: the material names and colours. Add the materials you need (a name, an sRGB byte triple and whether it glows); the colours are read by the game without gamma, so write what you want to see.
- `tools/models/records.py`: reads the machine record (`data/machines.sjson`, the `stone_furnace` entry: the footprint) and hands it to your script. Call `kit.expect_footprint(machine, 10, 10, 12)` first as the stub does.
- Your script: `tools/models/machines/stone_furnace.py`, `build(machine)`, replacing the stub. Keep the geometry deterministic (any randomness through `kit.model_random`).

## Commands (run them from this directory, pinned and niced because the client may be using the machine: prefix each with `taskset -c 8-15 nice -n 10`)

1. `tools/blender tools/make_models.py stone_furnace` builds the model in Blender headless and writes `data/models/stone_furnace.obj` and `.mtl`. Blender runs through Flatpak; the first start is slow.
2. `python3 check.py` prints the body's triangle count, its materials, the emissive ones, the bounds, and `OK` or the problems. Nothing is finished while it reports a problem.
3. `tools/blender render.py` renders five previews into `previews/`: `front_right`, `front_left` (the hero angle), `back_left`, `top` and `close`, with a player capsule beside the pad for scale. If Blender complains about a display, run `xvfb-run -a tools/blender render.py`. Look at every preview with the Read tool and compare it with the references, then iterate. Expect several rounds of build, check, render, look before the model is right; do not hand back the first thing that passes the check.

## The report

When the previews read as the reference sheet and the check says OK, report in at most 40 lines: the triangle count and the materials with their colours; the empty cells, if any; what you built and the choices you made where the images were ambiguous; what you would add with a larger budget; and the paths of the five previews. Do not paste code.
