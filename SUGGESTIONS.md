# Suggestions

Open questions that need the user's decision, each with the lead architect's recommendation, followed by proposed next steps. Decided items move to `doc/log/`.

## Decisions needed

1. License for the public repository. Without a license file the code is all rights reserved, which is unusual for a public repository. Permissive (MIT or zlib, matching Odin and raylib) or copyleft (GPL 3). Recommendation: decide before the first code commit.
2. Camera. First person (recommended: gyro aim gives precise block placement, and it is what Minecraft players expect) or third person.
3. Drills consume blocks and carve shafts (recommended: it keeps "dig anywhere" honest and makes depth visible) or drills mine abstract finite deposits and leave terrain intact.
4. Static water (recommended: cheap, predictable, no flooding accidents for kids) or flowing water.
5. Design the simulation for several players from the start (arrays of players and cameras). Recommended: it costs almost nothing now and keeps split screen co-op with the kids possible later.
6. Vertical range of the alpha world: fixed at 64 blocks above and 192 below sea level (recommended) or unbounded depth from the start.
7. Hand mining speed: fast, one to three seconds per block by hand (recommended for kids) or Minecraft pace.
8. Machine footprints: simplified even sizes chosen for gamepad alignment (recommended) or Factorio accurate sizes.

## Next steps

1. Discuss and settle the decisions above, then update `DESIGN.md` and log them.
2. Work item 0002, the Steam Controller input spike, before anything else. It decides whether the SDL3 direct path works on this machine with Steam running.
3. Work item 0001, toolchain skeleton and `build.sh`, so CI turns green and the Steam shortcut (0003) has something to launch.
4. Write `doc/world.md` (generation, strata, ore tables) and `doc/logistics.md` (belt lines, ramps, lifts, inserters) before M1 and M3 start.
