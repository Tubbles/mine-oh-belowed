# 0355: Cables and the power netlist

Status: todo (2026-11-11)

The user (2026-11-11), after The Last Caretaker: "Power: everything is hand run", then "No power rails", "Cable has capacity (we need to have a netlist based simulation, same for the fluids as well, no gravity)" and "saves with power poles just delete the poles". Today power poles join machines into pooled networks. 0353's study describes the reference's cables (`doc/inspiration.md`, The Last Caretaker) and its proposal is in `SUGGESTIONS.md`.

## Goal

Every power connection is a cable the player runs by hand from one thing to the next, each with a capacity, simulated as a netlist under the lockstep, and the power poles are gone.

## Controls

No new binding. The cable is a hotbar item, and running one is a mode the player enters and leaves with Place and Mine (control design, main agent, 2026-11-11):

- With the cable held and nothing carried, Place aimed at a thing with a free power port (a machine, a generator, a battery, a junction box) takes the cable's first end onto that port and begins the run. Aimed at anything else Place does nothing, with the reason shown as the other refusals are. The aimed thing is the target, not the port: a thing with several ports gives the free one nearest the aim.
- While a run is carried, the cable is drawn from its port to the player's hand and the tool line shows the length left of the span. Every movement control is unchanged. Place aimed at a second thing with a free port ends the run there and takes the cable's length from the stack. Aimed at nothing, at the first thing, or past the span, Place is refused with its reason (too short, no free port); the player is never held back by the cable.
- Mine while a run is carried takes the run back and ends the mode, as does selecting another hotbar slot. Mine digs and fells nothing during a run.
- With no run carried, Mine aimed at a cable takes it up into the inventory, as Mine picks up an aimed machine.
- Rotate_Building, Interact and Open_Inventory keep their meanings with the cable held and during a run. A machine's panel shows its port's draw, and a cable's load against its capacity is read on the junction box's panel and the power overview.
- A cable's capacity is its item (a light and a heavy cable are two items), never a setting cycled on a control. The junction box is placed as any machine.
- Touch reaches all of it through Place's and Mine's gamepad bindings.

## Change

- The cable as an item with a span, a port on every electric machine, generator and battery, a junction box that joins and branches. No rails: every machine takes its own cable.
- The power simulation as a netlist: nodes, the cables between them with their capacities, what a cable over its capacity does, in integers and deterministic, with the brownout and the power overview following it. It runs at all times over the whole world, also where the terrain and the models are unloaded (user, 2026-11-11), so its state stands apart from the loaded chunks.
- The small pole, the big pole and the substation leave the content. A save that holds them loads with them deleted and one log line; the quests, kits, technologies, recipes and blueprints that name them follow.
- The cable drawn between its two ends.
- Docs: `doc/fluids.md` (Power), `doc/content.md`, `doc/input.md`.

## Verify

- The checks and the suite, with a save holding poles that loads without them.
- Captures of a hand run factory of a handful of machines, sent to the user.
