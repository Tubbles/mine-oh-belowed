# 0016 Burner mining drill on veins

Status: todo
Milestone: M3

## Goal

The burner mining drill as described in `doc/logistics.md`: placed on a vein outcrop, tapping the reservoir with the vein's output mix, producing into the cell in front of its arrow, stalling on fuel or blocked output, and exhausting finite veins into spent rock.

## Deliverables

- Drill entity kind (2 by 2 by 2) with fuel slot, output arrow, cycle timing from `data/machines.sjson` (15 ore per minute plus spoil at the vein mix), placement validity requiring an outcrop cell of a vein under the footprint, vein handle stored on the drill.
- Reservoir draw with a deterministic generator seeded by tick and vein id, honouring the infinite veins world setting, exhaustion turning the outcrop to spent rock through `world_set_block`, and a drill state for it.
- Output through the transfer interface into the cell in front (belt, chest, machine that accepts the item); stall when blocked.
- Panel: fuel slot, vein remaining per ore, rate, state.
- HUD: the vein name and remaining amount when a drill or outcrop is targeted (the geologist's hammer assay comes later).
- Tests: placement validity on and off outcrops, draw mix over many cycles matching the vein weights within tolerance, exhaustion and spent rock, stall on blocked output and no fuel, shared vein between two drills, determinism.

## Verify

- Builds and tests pass.
- User: place a drill on the iron outcrop by the spawn, fuel it, and watch hematite fall into a chest in front of it.
