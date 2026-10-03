# The art direction booklet

The look of the machines, found in pictures on 2026-10-03 (work item 0211) before any machine is modelled again. The main agent wrote the briefs and prompts, `tools/art/generate.py` generated the images through OpenRouter (Nano Banana 2 for the rounds, Nano Banana Pro for the reference sheet, about 10 and 14 cents an image), the user reacted, the next round followed. The pages below keep one contact sheet per round with the user's verdict, then the kept image of every machine, then the stone furnace's reference sheet that 0212 models from. The originals (2400 by 1792 PNGs) and the rejected takes stay under `work/art/`, untracked; the images here are JPEG copies of a few hundred kilobytes.

The rules the booklet adds to the game's design are in [DESIGN.md](../../DESIGN.md), Art direction. What we take from other games is in [inspiration.md](../inspiration.md).

## The direction: astro-industrial punk

The user named it after round two: "combining 1) clean spacey panels, LEDs, LCDs, bright blinking colors, intriguing buttons and levers. with 2) rough, hard, dirty materials and grime, pipes, bolts, glass, metal, stone, brown, dark muted colors and gray. Almost like a juxtaposition." Every machine carries both worlds, and the ratio is the main theme of the technology progression: "the wood burning, coal and oil stages in the beginning slowly morphs into more cleanliness, futuristic droidy tech. But always a combination of the two, just it goes from 80/20 to 20/80 over the course of the game."

What the rounds taught about applying it:

- The two worlds interleave all over a machine. An industrial lower half under a clean upper half reads as a pattern at once and is forbidden (round four's verdict).
- Mid technology is cobbled together: clean modules wedged between rusty drums and pipes, LED strips wrapped round iron parts, screens bolted to the frame, cables everywhere, but still readable (lab mk2's second take was "way too chaotic and messy").
- Late technology is nearly all clean alloy, dusty and oil smudged, with an occasional vent, pipe, cog or bolted plate as the only rough parts, and no industrial base.
- Everything is dirty and used: dust, oil stains, grime in the seams, scuffs and dents, the pale panels smudged and worn. The clean technology still reads clean by its shape, its light and its colour, never by being spotless. Soot alone is not it: round two took "sootiness" literally and lost the kit.
- Every machine is automated, with no door and no room for a person inside. A shed with a workbench is a building, not a machine.
- Scale: the stone furnace stands about three astronaut heights to its chimney top and two wide. Presence comes from mass and from a few big readable volumes, not from detail.

## Round one: four directions

The stone furnace (left) and the mining drill (right) in four directions, the same camera and an astronaut beside the machine for scale: A a frontier foundry (cast iron and riveted steel over fieldstone, soot, Victorian industrial), B an expedition kit (pale alloy panels with hazard yellow trim on an exposed frame, in the manner of Techtonica and Astroneer), C a monolith (brutalist poured stone and bronze, cathedral scale), D low-fi stylized (flat colour planes, Dyson Sphere Program and Firewatch).

![Round one](booklet/round_1_sheet.jpg)

Verdict: "I love B, lets make the sparse colors pop a bit more, and bring in some of the darkness and sootyness from A."

## Round two: B with A's soot

B with saturated yellow and cyan accents and A's soot in four amounts (light soot, heavy soot, dark panels, an iron core), the furnace asked to stand three astronaut heights.

![Round two](booklet/round_2_sheet.jpg)

Verdict: the soot was taken too literally. The dirt wanted was A's Victorian industrial grime, short of steampunk, and the user named the direction (above).

## Round three: the spectrum on three stages

The stone furnace at 80 rough to 20 clean, the electric mining drill at half and half, the fusion reactor at 20 to 80, two takes each.

![Round three](booklet/round_3_sheet.jpg)

Verdict: "this round was really good, lets keep the rightmost column"; the fusion reactor without its stone bricks and dirtier, more dirt and grime on the furnace and the drill as well.

## Round four: the grime pass and six more machines

The kept three repainted grimier with the kept image as the reference (the reactor's masonry replaced by riveted iron), two fresh reactor takes, then the assembler (low), the rocket (mid) and the drone launch pad (high), and the labs mark one to three showing the gradient, two takes each.

![The grime pass](booklet/round_4_grime_pass.jpg)

![Round four](booklet/round_4_sheet.jpg)

Verdict: "very good", but mid and high tech "tend to do industrial bottom half, spacey top half", a pattern to break up; mid tech "much more cobbled together and chaotic in mixing the two", high tech "basically only spacey with the added grime and occasional vent, pipe, cog"; no shed structures, "these are all automated machines and there is no entering for an astronaut"; the assembler "a whirring hot mess of miniature arms, pistons, gears, belts, screwdriver-on-arms etc, like an actual miniature assembly line".

## Round five: the halves broken up

The eight machines again under those rules, two takes each; the furnace kept from the grime pass.

![Round five](booklet/round_5_sheet.jpg)

Verdict, the kept takes: assembler 2, lab mk1 2, drill 1 "but with only one drill shaft" (repainted so), rocket 2, lab mk2 1, reactor 1 ("love that one"), drone pad 2, lab mk3 1 (kept for not being a box, "but it has a bit too much of the industrial feel to it").

## The kept machines

Low technology, about 80 rough to 20 clean.

![The stone furnace](booklet/stone_furnace.jpg)

![The assembler](booklet/assembler.jpg)

![The laboratory mark one](booklet/lab_mk1.jpg)

Mid technology, about half and half, cobbled together.

![The electric mining drill](booklet/electric_drill.jpg)

![The rocket on its stand](booklet/rocket.jpg)

![The laboratory mark two](booklet/lab_mk2.jpg)

Late technology, about 20 rough to 80 clean.

![The fusion reactor](booklet/fusion_reactor.jpg)

![The drone launch pad](booklet/drone_pad.jpg)

![The laboratory mark three](booklet/lab_mk3.jpg)

## The stone furnace reference sheet

The kept furnace as the reference on every view, Nano Banana Pro. Single view prompts ("seen straight from the front", "seen from above") kept returning the reference's own three quarter angle, so the orthographic truth is the turnaround on one canvas and the plan drawing, both approved by the user with the hero view: the firebox mouth on the front face, the console on the left face, the pipes down the back, a small panel on the right. The footprint for 0212 is "as the images".

![The turnaround: front, left, back, right](booklet/stone_furnace_turnaround.jpg)

![The plan](booklet/stone_furnace_plan.jpg)

![The rear quarter with the astronaut](booklet/stone_furnace_rear_quarter.jpg)

![The mouth and the console](booklet/stone_furnace_mouth.jpg)

![The chimney and the pipes](booklet/stone_furnace_chimney.jpg)

## How the images are made

`tools/art/generate.py --model banana2 --ratio 4:3 --out work/art/<date>-<topic>/<name> --prompt "..."` writes `<model>_<index>.png` and appends the model, seed, ratio, cost and prompt to `prompt.txt` beside it; `--reference <image>` carries a kept image into a repaint (sent as a 1024 px JPEG, which is what the model needs). The prompts of every round are in the session scripts' history and in `prompt.txt`; the skeleton that worked: "Concept art for a factory building game on an alien planet: <the machine, its stage and ratio, what it is made of>. Style: <the direction paragraph>. Three quarter view from slightly above, an astronaut in a spacesuit standing beside it for scale, neutral overcast sky, clean uncluttered ground, no text". A reference sheet asks for "a model sheet turnaround ... four orthographic elevation views side by side on one canvas" and "a top down plan drawing ... as an architect's roof plan".
