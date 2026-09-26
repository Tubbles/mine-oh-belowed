# Suggestions

Open questions that need the user's decision, each with the lead architect's recommendation, followed by proposed next steps. Decided items move to `doc/log/`.

## Decisions needed

1. Progression channels. The user proposes that recipes are discovered when their prerequisite materials are produced for the first time. Recommendation: three channels. Discovery unlocks recipes exactly as proposed, and the recipe graph always shows undiscovered recipes as silhouettes (name and category visible, ingredients revealed on discovery) so the player can plan ahead. Lab research unlocks machine tiers and new processes (electrolysis, cracking, fracking), which keeps the research sink that drives scaling. Main quests deliver home world breakthroughs. A pure discovery model would leave nothing for the labs to do and would hide the goals players plan towards.
2. What labs consume. Grounded research kits assembled from the current tier's real products (a drill prototype to research better drills) instead of abstract coloured flasks. Recommended, it fits the realism lean and makes research a production problem.
3. Tools. Tools only multiply mining speed (recommended, following Wube's removal of pickaxes and ore hardness for adding explanation without decisions, see `doc/inspiration.md`), or tools also gate block hardness Minecraft style.
4. Rocket returns. Mission Control sends back both rare materials and schematics for alternate recipes (recommended), or only one of the two.
5. Vein numbers for the data files. Proposal, before the richness multiplier: scatterings 2k to 5k units, deposits 20k to 60k, concentrations 100k to 300k, deep veins five times their surface counterpart. Approve or adjust.
6. Byproduct strictness default. Strict by default, byproducts must be handled (recommended: it is the puzzle the user asked for), or lenient by default.

## Next steps

1. Settle the decisions above, then update `DESIGN.md` and log them.
2. Work item 0002, the Steam Controller input spike, before anything else. It decides whether the SDL3 direct path works on this machine with Steam running.
3. Work item 0001, toolchain skeleton and `build.sh`, so CI turns green and the Steam shortcut (0003) has something to launch.
4. Write `doc/world.md` (generation, strata, vein reservoirs, water), `doc/logistics.md` (belt lines, ramps, lifts, inserters, splitters), `doc/fluids.md` (network model, phases, gravity), `doc/quests.md` (objective types, chapter outline) and `doc/lore.md` (setting, Mission Control, naming glossary) before their milestones start.
