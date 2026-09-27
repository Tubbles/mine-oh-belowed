# 0048 Drills tap the vein footprint, not the outcrop blocks

Status: todo
Milestone: M10

## Goal

Couch test 1: the player mined every outcrop block near the pad by hand, after which no drill could be placed on the vein and the HUD no longer showed the vein when looking at the ground. A vein is a reservoir under a footprint disc (Manufactio's chunk bound veins, finer here), so drilling must depend on the footprint, never on which surface blocks are left.

## Deliverables

- Drill placement (`drill_vein_under` in `src/drill.odin`, used by `src/entity_placement.odin`) accepts a footprint cell whose column lies inside a registered vein's disc (`world.veins`, centre and radius), whatever block is on the surface. Outcrop blocks stay as the visible marker and keep giving ore when mined by hand. Bore drills keep their deep vein rule.
- The HUD vein line (`target_status_lines` in `src/ui_machine.odin`) shows the vein under any targeted block whose column lies in a footprint, mined or not; the geologist's hammer and the map keep their rules.
- Several veins in one chunk already work, since footprints are discs placed per region; confirm with a test and say so in `doc/logistics.md` and `doc/content.md` where the vein model is described.
- Tests: a drill placed on a footprint column whose outcrop block was mined is valid and mines; the HUD line for a plain block inside a footprint; two veins whose discs both reach one chunk both register and both take a drill.

## Verify

- Builds and tests pass.
- User: mine the outcrop blocks, place a burner drill on the same spot, ore flows.
