# Suggestions

Open questions that need the user's decision, each with the lead architect's recommendation, followed by proposed next steps. Decided items move to `doc/log/`.

## Decisions needed

1. Tools. Tools only multiply mining speed (recommended, following Wube's removal of pickaxes and ore hardness for adding explanation without decisions, see `doc/inspiration.md`), or tools also gate block hardness Minecraft style.
2. Rocket returns. The venture sends back both rare materials and schematics for alternate recipes (recommended), or only one of the two.
3. Vein numbers for the data files. Proposal, before the richness multiplier: scatterings 2k to 5k units, deposits 20k to 60k, concentrations 100k to 300k, deep veins five times their surface counterpart. Approve or adjust.
4. Byproduct strictness default. Strict by default, byproducts must be handled (recommended: it is the puzzle the user asked for), or lenient by default.

## Follow ups from the M1 implementation

Raised by the work item notes (0005 to 0008), to be turned into work items when they matter:

- Water and light that reach an unloaded chunk stop at the border and do not resume when the chunk loads.
- A saved chunk has no relight path: only generation computes sky light, so save and load (M5) needs a stored height map per column or a relight pass.
- Greedy meshing no longer merges faces with different corner light, doubling mesh time. A light aware merge or a coarser light quantisation would win it back if meshing shows up in profiles.
- All air and all solid chunks are stored in full; a single block id representation would roughly halve memory.
- Water covers about 29 percent of the surface, hills are capped at sea level plus 64, leaves are opaque. All one number each, waiting for the couch impression.
- Data files are not strict about unknown keys yet (`json.unmarshal` ignores them); the configuration strictness rule needs a custom check.
- Bindings are hardcoded tables until configuration lands. The raylib gamepad table lacks Sneak on B. Fly mode does not mine instantly yet.
- The third person camera can still clip into walls at steep angles, and the targeting ray starts at the eye in third person.
- Diagnostics overlay backdrop is narrower than its longest lines.
- Fluid branches are served in coordinate order (0020), so a tank on one branch can starve a consumer on another until the tank's fill fraction passes the junction's. Proportional sharing at junctions would fix it.
- Quest chapters measure placements and production, not layout (0018); an entity graph query would let quests check that pieces are actually connected.

## Next steps

1. Settle the decisions above, then update `DESIGN.md` and log them.
2. Continue the design topic list top down: review `doc/content.md` and `doc/quests.md`, then sound as feedback, the ending, strings and units in data, determinism and fixed point.
3. Work item 0002, the Steam Controller input spike, before anything else in code. It decides whether the SDL3 direct path works on this machine with Steam running.
4. Work item 0001, toolchain skeleton and `build.sh`, so CI turns green and the Steam shortcut (0003) has something to launch.
5. Write `doc/world.md` (generation, strata, vein reservoirs, prospecting, water, spawn requirements), `doc/logistics.md` (belt lines, ramps, lifts, inserters, splitters), `doc/fluids.md` (network model, phases, gravity) and `doc/lore.md` (the venture, Mission Control, naming glossary) before their milestones start.
