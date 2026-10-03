# 0198: The landing pod: larger, an airlock, a chest, a bench, an oxygen generator

Status: todo (user, 2026-10-03: "the landing pod should be larger, with an airlock, chest, crafting bench, it needs to house an oxygen generator and have infinite oxygen on board"; after 0197)

## Goal

The pod is the arrival of `DESIGN.md` (Arrival: an infinite water reserve feeding its oxygen generator, a bed, the first tools) and the sealed room of M15 (`PLAN.md`, Survival: the pod's oxygen generator and panels). Today it is 6 by 6 by 8 cells with a bed and a door (`pod()` in `tools/make_placeholder_models.py`, the record in `data/machines.sjson`, 0186's open cells).

## Change

- Larger: 8 wide by 12 deep by 8 high cells (4 by 6 by 4 m at the 500 mm pitch, the numbers in the record, so the user tunes them), in its crater (0199: no pad). The front 2 cells of depth are the airlock: an outer hatch on the front face and an inner hatch to the cabin, each 1 m wide and 2 m high.
- Hatches are a machine of kind `hatch`, 2 by 1 by 4 cells, placed by the world in the pod's wall cells: closed it is solid, Interact on it toggles it open (its cells become open cells, 0186) through the switch toggle path that exists (`Toggled_Switch`, `Power_Switch_Command`), so the airlock is two hatches the player opens one at a time. The hatch's state is lockstep state and saved. The model shows the hatch open or shut.
- Fixtures placed by the world inside the cabin, each a machine with its own footprint and panel, opened with the inventory binding (0194): the bed (as today, no panel), a `pod_locker` chest of 16 slots (the capsule's quest rewards keep going where they go today; say in the report if the locker should take them instead), a `crafting_bench` whose panel is the crafting view (hand crafting stays available everywhere in peaceful; in survival, M15, it is where crafting happens), and an `oxygen_generator` whose panel says what it does and shows "Oxygen: unlimited" for now. All are `machine_kind_is_placed_by_world` like the pod: never crafted, held or picked up (0195 refuses them).
- Infinite oxygen on board: the pod's cabin and airlock are registered as a sealed room with an unlimited oxygen supply (`Sealed_Room` on the simulation, the cells of the pod's open cells behind closed hatches), which M15's suit drain reads later. Until M15 nothing breathes, but the room exists, is saved, and the F3 World page says whether the feet are inside it.
- The model: `pod()` regenerated at the new size with the airlock chamber, the hatches' openings, the fixtures' footprints visible, the bed, windows and the band as today; the hatches and fixtures get their own placeholder models.
- `doc/content.md` (The pod, Hatches, the fixtures), `doc/architecture.md` (sealed rooms, the hatch's toggle), `PLAN.md` M15 (what this item already provides), the log.

## Controls

- Interact (F, gamepad South) on a hatch toggles it, the existing switch control; the hint reads "Open" or "Close". Open_Inventory (E, West) on a fixture opens its panel (0194). Nothing else is bound.

## Verify

- The build and check commands of 0168.
- Tests: the pod places in its crater with the two hatches and the fixtures at their cells; a closed hatch is solid and an open one is passed; toggling is lockstep state and round trips a save; the sealed room's cells are exactly the cabin and the airlock behind closed hatches; the fixtures refuse pick up and placement over them.
- The couch: the user opens the outer hatch, closes it, opens the inner one, reaches the locker, the bench and the generator, and F3 says "inside the pod".
