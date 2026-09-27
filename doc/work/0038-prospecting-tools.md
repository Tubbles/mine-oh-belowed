# 0038 Prospecting tools

Status: implemented
Milestone: M8

## Goal

The prospecting ladder from DESIGN.md as far as the alpha needs it: the geologist's hammer assay, the magnetometer with trackpad haptics, the core sample drill for deep veins, and the seismic survey, each revealing one attribute on the map.

## Deliverables

- Map overlay layers: the top down map (a new screen, the world seen from above around the player at chunk resolution with explored area only, from the chunk heights and biomes) gets layers for assayed vein footprints, magnetometer readings, core samples and seismic outlines.
- Geologist's hammer (a tool item, start channel): Use on an outcrop block assays the vein: ore mix, size class, footprint marked on the map. The HUD already names the vein of a targeted outcrop; the assay adds the footprint and persists it.
- Magnetometer (handheld tool, `prospecting` technology): while selected, a reading of the nearest iron bearing vein within 30 blocks including buried deep veins, shown as a needle and strength on the HUD and as trackpad haptics on the SDL3 backend (rumble the right pad proportional to strength; if SDL exposes no pad haptics for the Steam Controller, use the controller rumble and note it).
- Core sample drill (entity, 1 by 1 by 2, electric 40 kW, `prospecting`): after 60 seconds reports the strata below and any deep vein under its column with composition and depth, marks the column on the map.
- Seismic survey (`seismic_survey` technology, packs 1 and 2): thumper charges (an item, 5 sulfur and 2 iron plate) placed on the ground and triggered with Use image deep veins within a radius of 32 blocks as outlines on the map; three or more shots resolve a vein's shape fully.
- Orbital survey is phase 8 (a shipment), not here.
- Tests: assay data, magnetometer nearest vein and strength, core sample report, seismic outline union over several shots, map layer persistence in the save.

## Verify

- Builds and tests pass.
- User: strike an outcrop and see its footprint on the map, follow the magnetometer buzz to a buried iron vein, and outline a deep vein with three charges.

## Notes

- Carry over from 0037 done first: wire reach now measures between footprint centres (across, at the bottom), in doubled integer coordinates so a 2 by 2 centre stays exact (`src/power_network.odin`). 1 by 1 poles connect exactly as before. Test: `test_substation_wire_reach_measures_from_the_footprint_centre`. doc/fluids.md "As implemented in 0037" still says the reach measures from a corner and needs a line; the comment in data/machines.sjson is updated.
- Usable items got a `use` field in items.sjson (`read`, `assay`, `magnetometer`, `seismic_shot`) with `detects` and `use_range`, so no item id is named in code. Schematics and fired thumper charges are consumed, the hammer and the magnetometer are not (`use_consumes_item`); a charge is only used up when the previous tick's target hit a block.
- Records live on the World and are saved in entities.bin after the crate sites: explored columns (sorted), assayed veins, magnetometer readings, core samples, seismic shots and outlines. The layout fingerprint changes, so saves from before this item are refused (as with every layout change so far).
- Explored set: a chunk column is explored when any chunk of it is inserted. Its surface record (block and height per block column, 4 bytes each, 4 KiB per column) is refreshed from the loaded chunks when a chunk of the column unloads and before every save. A scan only replaces a stored cell when it started at least as high as the stored height, so being deep underground with the surface chunks unloaded keeps the surface. The map reads loaded columns live when it opens.
- Map: one 256 by 256 image, zoom 1, 2, 4, 8 or 16 blocks per pixel (opens at 2), painted on the CPU and uploaded as one texture (`Draw_Command.Image`, `Ui_Image_Cache` in ui_draw.odin); repainted when the view moves and every 0.5 s for entities and records. Layers: surface block top colour shaded by height, entity cells as white dots, assayed discs tinted, seismic outlines as circles (brighter when resolved), core samples as crosses (yellow over a deep vein), magnetometer readings as a dot with a line towards the vein as long as the reading was strong; the player is a UI marker with a facing dot. Right bumper, wheel up and right stick up zoom in; left stick, WASD or a pointer drag pan; B or Open_Map (View, M) closes. The Open_Map bindings are now context `both` since they also close the map (the context field only documents).
- Magnetometer: reads the registered veins only (those whose chunk columns were loaded once), which covers the 30 block range around a player in practice. Distance is measured across only, from the player to the nearest column of the disc, so a deep vein counts at any depth (the work item asks for buried deep veins; measured in 3D they are 40 to 120 blocks down and never in range). Strength is 1 inside the disc falling linearly to 0 at 30 blocks.
- Haptics: SDL3 has only `SDL_RumbleGamepad` for this controller (doc/input.md), no per pad haptics, so both motors rumble at the strength, renewed every frame for 100 ms and stopped when the strength drops to 0 or a screen opens (`Frame_State.haptic`, `apply_sdl3_haptics`). The raylib backend does not rumble.
- Core sample drill: its own entity pool (`Core_Sample_Drill`), electric 40 kW, `sampling_seconds = 60` of powered work (a brownout lengthens it), then one report; picked up and placed again it samples anew. Strata are the most common block per 16 block band for 8 bands (128 blocks), read from loaded chunks only: the report stops at the first band reaching an unloaded chunk (shown as "not reached"). The deep vein is the registered one whose disc holds the column, with type (hence mix) and depth from the drill's origin to the vein centre.
- Seismic: `seismic_survey` (100 packs of science packs 1 and 2, 30 s per pack is a guess, prerequisite prospecting) unlocks `thumper_charge` (5 sulfur, 2 iron plate, 4 charges, 1 s, tools tab; stack size 50 is a guess; category tool). A shot records every registered deep vein whose disc reaches within 32 blocks of the shot (centre distance at most 32 plus the radius) as one outline per vein (the union), counting the shots; the third resolves it (statistic only). Shots at the same spot count again.
- Statistics and hint counters for chapter 7: `veins_assayed`, `core_samples_taken`, `seismic_shots`, `veins_resolved`.
- The hammer mines like a stone pickaxe since 0051 gave it tool tier 2 (pickaxes had no effect in code before that).
- Guessed numbers: map image size, zoom steps, pan speed, repaint interval, colours, band depth and count, rumble renewal time, thumper charge stack size and research time.
- Not verified: nothing was seen in a window or felt on a controller. The map screen, its texture upload, the HUD dial, the needle direction on screen and the rumble are compiled and partly unit tested (map frame and painting, needle angle, haptic request) but never run.
- Docs that need a line from the main agent (outside this item's files): doc/ui.md (map screen, magnetometer dial), doc/input.md (the rumble), doc/fluids.md (wire reach from footprint centres), doc/content.md (thumper charge recipe and seismic_survey technology), DESIGN.md Prospecting if the seismic simplification (one circle per vein, no shape) should be recorded.
- Open questions: should a resolved vein show its real disc while unresolved ones show something coarser (now both are the true circle)? Should the magnetometer read veins in columns never loaded (it would need the generator in the simulation)? Should the map show deep veins found by the core sample drill as discs?

