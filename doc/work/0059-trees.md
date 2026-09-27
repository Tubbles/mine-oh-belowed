# 0059 Bigger trees, species, felling

Status: todo
Milestone: M11

## Goal

Trees are a trunk of a few blocks under a fixed crown. Species per biome, trunks of eight to sixteen blocks, real crowns, roots and clearings, and a felled trunk brings its crown down.

## Deliverables

- Tree species in `data/biomes.sjson`: trunk height range, crown shape (round, conical, flat), leaf and log blocks, density, clearings.
- Generation places crowns of several layers with roots at the base; forests dense with clearings; the outcrop clearing rule (0045) keeps footprints open.
- Felling: mining a trunk block drops the logs above it and the crown decays over a few seconds into leaf litter and saplings that count as items, so no floating canopies remain.
- Tests: species placement, no floating leaves after a felling in a test world, the landing site rule.
- Moved here from 0058: a tree species for every biome, the climate biomes (cold barrens, highland, badlands, steppe, wetland, coastal dunes) included, which until then grow the one tree shape at their `tree_density`.

## Verify

- Builds and tests pass.
- User: Fell a tree on the couch; screenshots.
