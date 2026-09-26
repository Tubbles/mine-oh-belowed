# Suggestions

Open questions that need the user's decision, each with the lead architect's recommendation, followed by proposed next steps. Decided items move to `doc/log/`.

## Decisions needed

1. Tools. Tools only multiply mining speed (recommended, following Wube's removal of pickaxes and ore hardness for adding explanation without decisions, see `doc/inspiration.md`), or tools also gate block hardness Minecraft style.
2. Rocket returns. The venture sends back both rare materials and schematics for alternate recipes (recommended), or only one of the two.
3. Vein numbers for the data files. Proposal, before the richness multiplier: scatterings 2k to 5k units, deposits 20k to 60k, concentrations 100k to 300k, deep veins five times their surface counterpart. Approve or adjust.
4. Byproduct strictness default. Strict by default, byproducts must be handled (recommended: it is the puzzle the user asked for), or lenient by default.

## Next steps

1. Settle the decisions above, then update `DESIGN.md` and log them.
2. Continue the design topic list top down: review `doc/content.md` and `doc/quests.md`, then sound as feedback, the ending, strings and units in data, determinism and fixed point.
3. Work item 0002, the Steam Controller input spike, before anything else in code. It decides whether the SDL3 direct path works on this machine with Steam running.
4. Work item 0001, toolchain skeleton and `build.sh`, so CI turns green and the Steam shortcut (0003) has something to launch.
5. Write `doc/world.md` (generation, strata, vein reservoirs, prospecting, water, spawn requirements), `doc/logistics.md` (belt lines, ramps, lifts, inserters, splitters), `doc/fluids.md` (network model, phases, gravity) and `doc/lore.md` (the venture, Mission Control, naming glossary) before their milestones start.
