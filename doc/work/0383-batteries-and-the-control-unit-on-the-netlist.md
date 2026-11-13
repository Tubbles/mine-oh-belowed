# 0383: Batteries and the control unit on the netlist

Status: designed (2026-11-13)

Step 2 of 0368's specification (`0368-cables-junction-boxes-and-the-poles-removal.md`, Steps and "Batteries and the control unit (step 2)"), split off at its approval. Until it lands a vessel part with a power port is a node that only passes power on.

## Goal

A vessel's batteries store and give power through the cables, and its control unit draws its 60 W from them.

## Controls

None.

## Change

- As 0368's specification, step 2: batteries as stores (`Vessel_Part.power`, `stored_joules`, `STORE_DISPATCH_ORDER`), the control unit as a consumer, the save's and the hash's fields that follow. Simulation only.
- After 0368. Independent of 0384.

## Verify

- The checks and the suite, with the tests 0368's specification names for step 2.
- An older save loads with its batteries empty or as the specification says, and one log line.
