# 0357: The crawler

Status: todo (2026-11-11)

The user (2026-11-11), on The Last Caretaker's vessel as a base: "a land based one for now that you build up and improve like a ship of theseus", "pod stays, the vehicle is built from scratch. New planets need new vehicles from scratch", and of 0353's three shapes: "Crawler is fine". 0353's proposal: two tracks under a deck that is a foundation frame, moved without physics so the lockstep holds (`SUGGESTIONS.md`).

## Goal

A crawler the player builds from scratch, builds on, drives over the planet and improves part by part.

## Controls

The main agent writes the control design before the design stage starts: the driving mode or seat, what the sticks do in it, how it is entered and left, and what every world control does while driving (Code rules, keybindings).

## Change

- Built on 0361: the crawler is a vessel of that system, and this item makes a vessel's frame move. Its pose changes every tick, set from the terrain under its tracks in integers, with speed and the climb limit from the vessel's figures; a player and everything on it carried with it; tied, and so parked, while a cable or a pipe joins it to another frame (`vessel_is_tied`). What a moving frame hits in the renderer is in 0347's decision 9 (the frame table's revision mixing occupancy and pose, no pose interpolation, runs in world positions).
- A sandbox, no slots (user, 2026-11-11: "I don't like prebaked slots on the vessel though, I want to capture the sandbox feel from TLC"): the crawler is built freely on its own grid from structure pieces (deck, wall, ramp, rail) and track units, grown in any direction, and each piece replaced by a better one in place. What bounds it is numbers, not slots: the mass the tracks carry and the power they draw, in integers from data.
- What is placed on it is vessel equipment, not the factory's machines (user, 2026-11-11: "vessel oriented power up machines"): a kind in data says where a thing mounts (the ground, a vessel, both), with a first list for the design to propose (battery bank, charging cradle, hold, fabricator, lamp mast, scanner, cable reel). On board they are joined by hand run cables as on the ground (0355); belts and pipes on board are not part of this item.
- Everything on the deck is simulated in full while it drives (user, 2026-11-11: "Full physics sim on the deck"): machines work, belts carry, bodies stand and collide. What rides on the deck and what stands on the ground. The vessel itself moves by full physics, never by a pose set from the terrain (user, 2026-11-11: "Vessel has full physics, no pose on terrain"): a rigid body with mass and momentum that slides, tips and gets stuck, in fixed point so every machine computes the same motion. 0353's kinematic proposal (line 5) is overturned.
- A new planet's crawler starts from that planet's material.
- The renderer draws a frame that moves (0346 and 0347 must allow it).
- Docs: `doc/architecture.md` (Frames), `DESIGN.md` (Building), `doc/input.md`.

## Verify

- The checks and the suite, with the state hash of a drive equal on two machines.
- A capture series of a drive over a ridge with a workshop on the deck, sent to the user.
