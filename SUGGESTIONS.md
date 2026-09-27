# Suggestions

Open questions that need the user's decision, each with the lead architect's recommendation, followed by proposed next steps. Decided items move to `doc/log/`.

## Decisions needed

Balance and design questions are deferred (user, 2026-09-27): the play experience (sound, textures, models, animations), lore and depth come first, and game balancing belongs to late beta, just before the first release. We are before the first alpha, so nothing here is decided arbitrarily now.

Decided on 2026-09-27: tools gate block hardness as well as mining speed (work item 0051); infinite research empties the queue after each level (done).

Deferred to the design and balance phase, with the current behaviour kept until then: rocket returns (rare materials, schematics or both; today both); the vein size numbers (scatterings 2k to 5k units, deposits 20k to 60k, concentrations 100k to 300k, deep veins five times); the byproduct strictness default (strict: a machine whose byproduct output is full waits; lenient: byproducts that do not fit are voided and counted; today strict), pending the byproduct redesign noted in `DESIGN.md`; whether a late orbital survey contract pays a smaller survey radius instead of the full survey; where the infinite technologies sit in the tree (today behind rocket program).

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
- Bindings are a list overridden per action (0025); an object keyed by action would merge better across layered files, and there is no way to unbind an action (a `none` control). The `context` field is displayed but does not gate actions.
- The log file grows without limit and argument errors before the log opens reach stderr only.
- Saves refuse any change to data ids or struct layout (0023); work item 0047 makes them survive additive changes.
- The load screen shows one long string per world; columns would read better on the couch. World setting choices step forward only; left and right should step back.
- A player built roof over a saved chunk does not darken it on reload (0023), the same gap as generation under a roof.
- The set of found schematics rides on the recipe registry value (0036) so fixed recipe machines can check it without a new parameter through every machine path; session state on a data table is a smell worth removing with an explicit availability parameter once the machine paths settle.
- Sulfur has no consumer yet (0031); sulfuric acid and batteries in phase 7 are the natural users. Fast belts remain a placeholder technology until a second belt speed exists, which needs belt placement and rendering to read the speed from the machine.
- `generate_chunk_blocks` grows the outcrop and crate lists inside its temporary allocator guard, so a caller that passes temporary allocated lists gets them corrupted; the streaming path passes heap lists and the 0045 determinism test avoids it.
- Drill placement by footprint (0048) checks the column, not the height: a drill on a platform above or in a cave below a vein taps it, and a surface drill can be placed over an exhausted vein (which the revival design wants). A height band around the surface would tighten it if the couch minds.
- Fonts (0077): the headless UI audit approximates text width with the default face's average advance (0.37 of the size); Michroma, Orbitron and Oxanium are wider (0.42 to 0.44), so overflow with them can slip past the audit until it takes a per family factor from fonts.sjson.
- Hot reload (0054): block light in loaded chunks is not recomputed after a content reload (an emission change waits for a remesh of light), and a changed vein type keeps registered veins' old records, so outcrops in chunks generated later can disagree with the registry until the world reloads.
- Command socket (0053): `place` does not count as a player placement for quests (use `chapter` to advance); a blueprint's `{vein}` origin needs the vein's chunks loaded, since it reads registered veins rather than the generator's starter veins; veins added by command are invisible to the map survey and the orbital survey, which read the generator.
- The orbital survey (0041) asks the generator for about 25 regions of vein placement on the main thread inside one tick; its cost at the 256 block radius was not measured. The catalogue buttons and the pad panel tabs have not been seen with the gamepad's focus movement.

## Next steps

1. Settle the decisions above, then update `DESIGN.md` and log them.
2. Continue the design topic list top down: review `doc/content.md` and `doc/quests.md`, then sound as feedback, the ending, strings and units in data, determinism and fixed point.
3. Work item 0002, the Steam Controller input spike, before anything else in code. It decides whether the SDL3 direct path works on this machine with Steam running.
4. Work item 0001, toolchain skeleton and `build.sh`, so CI turns green and the Steam shortcut (0003) has something to launch.
5. Write `doc/world.md` (generation, strata, vein reservoirs, prospecting, water, spawn requirements), `doc/logistics.md` (belt lines, ramps, lifts, inserters, splitters), `doc/fluids.md` (network model, phases, gravity) and `doc/lore.md` (the venture, Mission Control, naming glossary) before their milestones start.
