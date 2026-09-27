# 0048 Drills tap the vein footprint, not the outcrop blocks

Status: implemented
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

## Notes

`vein_at_column` (`src/world_vein.odin`) returns the registered surface vein whose disc holds a column, deep veins excluded. `drill_vein_under` and the HUD vein line use it; `outcrop_vein_at` is left to the geologist's hammer. Tests: `test_drill_mines_a_footprint_whose_outcrop_was_mined`, `test_hud_names_the_vein_under_a_plain_block_in_its_footprint`, `test_two_veins_in_one_chunk_both_take_a_drill`; `test_drill_placement_needs_a_vein_outcrop` now expects a footprint with its outcrop replaced by stone to be valid.

### Side effects

- A surface drill can now be placed over an exhausted vein (its outcrop is spent rock, but the footprint remains). It reads as exhausted, and a drill with a revival port revives it.
- The footprint is a column rule, so a drill standing at any height in the column (a cave, a built platform) finds the vein, and the HUD names the vein for any block in the column, above or below ground.
