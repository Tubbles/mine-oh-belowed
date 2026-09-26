# Suggestions

Open questions that need the user's decision, each with the lead architect's recommendation, followed by proposed next steps. Decided items move to `doc/log/`.

## Decisions needed

1. What a mining drill does to the world. Options: (a) ore blocks become air, leaving a narrow shaft the size of the drill footprint; (b) ore blocks become spent rock, a plain stone block, so the terrain stays solid and only the ore is gone (recommended: no craters, exhaustion is visible when tunnelling past the vein, hand mining and drill mining stay the same act); (c) drills draw from an abstract deposit counter and the terrain never changes (rejected by the design pillars unless the user prefers it).
2. Static water (recommended: cheap, predictable, no flooding accidents for kids) or flowing water.
3. Vertical range of the alpha world: fixed at 64 blocks above and 192 below sea level (recommended) or unbounded depth from the start.
4. Hand mining speed: fast, one to three seconds per block by hand (recommended for kids) or Minecraft pace.
5. Machine footprints: simplified even sizes chosen for gamepad alignment (recommended) or Factorio accurate sizes.

## Next steps

1. Settle the decisions above, then update `DESIGN.md` and log them.
2. Work item 0002, the Steam Controller input spike, before anything else. It decides whether the SDL3 direct path works on this machine with Steam running.
3. Work item 0001, toolchain skeleton and `build.sh`, so CI turns green and the Steam shortcut (0003) has something to launch.
4. Write `doc/world.md` (generation, strata, ore tables) and `doc/logistics.md` (belt lines, ramps, lifts, inserters) before M1 and M3 start.
