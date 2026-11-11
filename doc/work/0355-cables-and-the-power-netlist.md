# 0355: Cables and the power netlist

Status: todo (2026-11-11)

The user (2026-11-11), after The Last Caretaker: "Power: everything is hand run", then "No power rails", "Cable has capacity (we need to have a netlist based simulation, same for the fluids as well, no gravity)" and "saves with power poles just delete the poles". Today power poles join machines into pooled networks. 0353's study describes the reference's cables (`doc/inspiration.md`, The Last Caretaker) and its proposal is in `SUGGESTIONS.md`.

## Goal

Every power connection is a cable the player runs by hand from one thing to the next, each with a capacity, simulated as a netlist under the lockstep, and the power poles are gone.

## Controls

The main agent writes the control design before the design stage starts: how a cable is taken, carried from a port to a port and taken up again on a gamepad, on which layer, and what every existing control does with a cable in hand (Code rules, keybindings).

## Change

- The cable as an item with a span, a port on every electric machine, generator and battery, a junction box that joins and branches. No rails: every machine takes its own cable.
- The power simulation as a netlist: nodes, the cables between them with their capacities, what a cable over its capacity does, in integers and deterministic, with the brownout and the power overview following it. It runs at all times over the whole world, also where the terrain and the models are unloaded (user, 2026-11-11), so its state stands apart from the loaded chunks.
- The small pole, the big pole and the substation leave the content. A save that holds them loads with them deleted and one log line; the quests, kits, technologies, recipes and blueprints that name them follow.
- The cable drawn between its two ends.
- Docs: `doc/fluids.md` (Power), `doc/content.md`, `doc/input.md`.

## Verify

- The checks and the suite, with a save holding poles that loads without them.
- Captures of a hand run factory of a handful of machines, sent to the user.
