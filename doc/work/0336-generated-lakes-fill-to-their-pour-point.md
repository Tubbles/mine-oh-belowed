# 0336: Generated lakes fill to their pour point

Status: todo (2026-11-07)

From 0334's design. Under the bodies model, the 8 km planet's lake 27 (79.46 N, 40.95 E, 3 m deep) is generated 0.69 samples over the pour point the bodies' flood finds for it. It drains about 680k fill over its sill, and every flood splits its layer over the sill to the front, which seeds and merges it again, so it settles only after 979 to 2,622 ticks, depending on the order its chunks arrive (`tmp/0334/sweep_fix_arena.log`). 0312's refine sets the level on its 2 m grid sealed on the 1 m lattice; the flood finds the pour point on the samples.

## Goal

Every generated lake at 4, 8 and 16 km stands at or under the pour point the bodies' flood finds, so it is at rest from the tick its chunks arrive.

## Controls

None.

## Change

- The refine's level agrees with the flood's pour point on the samples (the generation fills to the lower of the two, or reads the sill as the flood does). Or, if the design finds the flood's pour point wrong, the flood keeps an over-sill body's top layer as its volume.
- Old worlds keep their lakes through the record (0312's waters), or the change is recorded with one log line.
- Docs: `doc/architecture.md` (World generation, the waters), the log.

## Verify

- The checks and the suite, with a test that every generated lake at the three presets stands at or under its flood's pour point, and lake 27 at 8 km settling under bodies within a few ticks of its last chunk.
