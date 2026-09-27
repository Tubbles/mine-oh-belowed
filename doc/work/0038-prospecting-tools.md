# 0038 Prospecting tools

Status: todo
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
