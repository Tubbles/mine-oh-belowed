# Suggestions

Open questions that need the user's decision, each with the lead architect's recommendation, followed by proposed next steps. Decided items move to `doc/log/`.

## Decisions needed

1. Tools. Tools only multiply mining speed (recommended, following Wube's removal of pickaxes and ore hardness for adding explanation without decisions, see `doc/inspiration.md`), or tools also gate block hardness Minecraft style.
2. Quests. Quests guide and reward only, the technology tree is the sole gate (recommended: a player who ignores the journal is never blocked), or quests also gate research.
3. Rocket returns. Mission Control sends back both rare materials and schematics for alternate recipes (recommended), or only one of the two.
4. Vein numbers for the data files. Proposal, before the richness multiplier: scatterings 2k to 5k units, deposits 20k to 60k, concentrations 100k to 300k, deep veins five times their surface counterpart. Approve or adjust.
5. Byproduct strictness default. Strict by default, byproducts must be handled (recommended: it is the puzzle the user asked for), or lenient by default.

## Next steps

1. Settle the decisions above, then update `DESIGN.md` and log them.
2. Work item 0002, the Steam Controller input spike, before anything else. It decides whether the SDL3 direct path works on this machine with Steam running.
3. Work item 0001, toolchain skeleton and `build.sh`, so CI turns green and the Steam shortcut (0003) has something to launch.
4. Write `doc/world.md` (generation, strata, vein reservoirs, water), `doc/logistics.md` (belt lines, ramps, lifts, inserters, splitters), `doc/fluids.md` (network model, phases, gravity) and `doc/quests.md` (objective types, chapter outline) before their milestones start.
