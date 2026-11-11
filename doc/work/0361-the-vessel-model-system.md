# 0361: The vessel model system

Status: todo (2026-11-11)

The user (2026-11-11): "I want to have some \"Theseus model system for vessels\" that includes the crawler among other vessels, space ship, rocket etc.", "Think generic slots and keep the cables for power and fluids, so we need to hook it all up as we place it down. E.g. liquid rocket stage: place fuselage, place tanks for fuel and oxygen, place engine, hook up fluid pipes, place batteries, hook up power lines", and before it "I don't like prebaked slots on the vessel though, I want to capture the sandbox feel from TLC". The draft the user was sent is `work/vessel_model_system.md`; the user then asked for the design. Its six questions are not answered, so the design takes the draft's proposals and marks each as the main agent's, for the user to overturn.

## Goal

One system builds every vessel: structure that snaps freely and brings generic slots, equipment placed into slots, every cable and pipe run by hand, what the vessel can do computed from its parts, and any part swapped for a better one in place.

## Controls

No new binding and no new mode. Placing stays Place with the part held, and what is aimed at decides where it goes, as the inventory binding opens the aimed machine:

- A structure piece held: the ghost snaps to the aimed free face of a vessel's structure, or to the ground to begin a vessel. Rotate turns it as it turns a machine's ghost.
- Equipment held: the ghost snaps into the aimed free slot of its size. Rotate turns it through the orientations the slot allows. Aimed at no slot, there is no ghost and Place does nothing, with the reason shown as the other refusals are.
- A part held and aimed at a part of the same size or shape and a lower tier: the ghost shows the replacement and Place swaps it in place.
- Taking a part off is the existing removal, refused while something is attached that would be left without a slot.
- Cables and pipes are 0355's and 0356's controls, unchanged on a vessel.
- The vessel's panel opens with the inventory binding aimed at the control unit.
- The placement editor (0215) is not used for vessel parts: a slot fixes the position.

## Change

- The part table in data: structure and equipment, sizes, the slots a structure piece brings (a size and a side each), ports, mass, storage, what a part delivers when fed, tiers.
- A vessel as a frame holding its parts, its slots' contents and its connections, in the simulation state, hashed and saved.
- Placement into slots and onto structure faces, removal, and the swap in place that keeps the connections whose ports remain.
- The computed figures (mass, power, drive) in integers, recomputed when a part or a connection changes, and the panel that shows them with what is not hooked up.
- The connector that joins a vessel's netlists to the ground's, and the rule that a connected vessel does not move.
- This item ends with a vessel that is built, hooked up and upgraded while standing still. The crawler's motion is 0357, rewritten on this; the rocket stage and the decoupler are an item after 0356.
- Docs: a new `doc/vessels.md`, `DESIGN.md` (Building), `doc/content.md`, `doc/input.md`.

## Verify

- The checks and the suite, with a vessel built, hooked up, saved, loaded and one part of each role swapped, the state hash equal on two machines.
- Captures of a small vessel being built and of its panel with one connection missing, sent to the user.
