# 0383: Batteries and the control unit on the netlist

Status: landed (2026-11-13, 7ebe0e1)

Step 2 of 0368's specification (`done/0368-cables-junction-boxes-and-the-poles-removal.md`, Steps and "Batteries and the control unit (step 2)"), split off at its approval. Until it lands a vessel part with a power port is a node that only passes power on.

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

### Deviations (implementation, 2026-11-13)

- The docking connector gains a second power port, `power_inner` (index 2, -z, 5000 W), appended to its `ports`. A port takes one cable, so with one power port the connector could take the ground's cable or a cable to the battery, never both, and the specification's test (and any ground charge in play) could not be built.
- A battery is a participant with `generator` and `store` both set, its order set where it is made (`make_battery_participant`), so it is never counted unpowered; it counts in `store_count`, not `generator_count`.
- The old save's log line, which Verify asks for and the specification did not place: `read_vessel_tables` reads the parts' schema for `stored_joules` (`saved_list_has_field`) and logs once when it lacks it and the save holds a vessel.
- After the review (main agent's decisions): a vessel's own network, a tree whose participants are all vessel parts (`Electric_Network.ground_participant_count` 0), is left out of `unpowered_machines`, `brownout_ticks` and the HUD's brownout warning, against the specification's `record_electric_tick` rule; a tree with a ground participant counts as any network.
- The power overview lists the batteries apart: a "Batteries" count line (`power_overview_batteries`) and up to `POWER_BATTERY_TYPE_COUNT` (2) groups, each showing what it gave and, marked +, what it took. The specification left `ui_power.odin` unchanged.
- `energy_produced_joules` is what the generators gave, their charge of batteries included, never a battery's discharge; consumed stays what the consumers received.
