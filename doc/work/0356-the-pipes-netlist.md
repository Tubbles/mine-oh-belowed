# 0356: The pipes' netlist

Status: todo (2026-11-11)

The user (2026-11-11): "we need to have a netlist based simulation, same for the fluids as well, no gravity". Today pipes carry liquids and gases in one network model in which liquids run downhill for free and need pumps to climb (`doc/fluids.md`). The world's water (lakes, the sea, streams, the water bodies) is the terrain's and is not this item.

## Goal

The pipes are simulated as a netlist, as power is in 0355, with no gravity in a pipe.

## Controls

None.

## Change

- The pipe network as nodes and the pipes between them with their capacities, in integers and deterministic; what moves a fluid when height no longer does (pumps, pressure from a source, a tank's level), decided in the design against 0355's netlist so the two share what they can.
- A save's pipe networks load into it, with one log line where a network that ran by gravity no longer flows.
- The quests and kits that teach water running downhill in a pipe follow.
- Docs: `doc/fluids.md`, `doc/content.md`.

## Verify

- The checks and the suite, with the dev kits' fluid lines running at their rates.
