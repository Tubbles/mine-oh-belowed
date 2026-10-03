# 0197: Trees on the planet

Status: designed (2026-10-03, the specification approved; after 0199; implied by 0196, 2026-10-03: wood must come from somewhere before tree farms; after 0196)

## Goal

Logs come from the planet. Today `log` is mined from the block world's tree blocks (`mined_from` in `data/items.sjson`), and the field planet has no trees, so a field world's only wood is its kit.

## Change

- A first pass of trees as field entities: a trunk and a crown placed by the planet generation on the surface above the sea by a hash of the sample (so the same seed grows the same trees on every machine), in groves rather than evenly (no perceivable repetition, `DESIGN.md`), none on the home's pad.
- Mine held on a trunk in reach fells it after a few seconds (the block world's rule for a log block, `PICK_UP_SECONDS` or the block's mining time) and yields logs; the crown goes with it. A tree is a save entity and a generation one: a felled tree is remembered in the save, the rest regenerate.
- The planet record names the density and the species' model and tint (`data/planets.sjson`), the tree's model is a placeholder as the pod's is (`tools/make_placeholder_models.py`).
- `doc/content.md` (Trees), `doc/architecture.md` (the field's entities, the generation), the log.

## Controls

- Mine on a trunk, the same control as mining the ground and picking up (0195); the hint beside a trunk reads "Fell".

## Verify

- The build and check commands of 0168.
- Tests: the same seed places the same trees; a felled tree yields logs and stays felled after a save and load; no tree stands on the pad; the hash agrees on two sessions.
- The couch: the user fells a tree near the home and planks a pad.

## Specification (design, 2026-10-03)

Designed against `main` at 71611c4 plus the uncommitted 0189 tree in the main checkout (`surface_relief` with its shape terms, `Relief_Shape`), and against the approved specifications of the items that land before this one and are not on `main`: 0199 (the crater term: `uncratered_relief`, `crater_relief`, `Planet_Crater`, `crater` and `crater_recorded` in `Planet_Generation_Record`, `CRATER_RIM_FALL_PER_HEIGHT`), 0204 (the OBJ reader and the Blender kit; the kit's names below were read off its worktree `.claude/worktrees/0204`: `kit.cylinder(centre, start, end, radius, sides, material_name, bevel=0.0, axis="Z")`, `kit.cone(centre_xy, z0, z1, radius_bottom, radius_top, sides, material_name, rotation=0.0)`, `kit.join(objects, name)`, `palette.MATERIALS`, `tools/models/machines/__init__.py` `MACHINES`), 0207 (`build(machine)` with a `records.Machine`, `tools/make_models.sh`, `tools/model_preview.sh`, `--model-check`, `test_the_shipped_models_pass_the_checks`, the maxima of 800 triangles per body and 8 materials) and 0196 (`log` to planks, the kit's 8 planks, `test_the_slice_recipe_chain_is_reachable_from_the_fields_yield`). Where one of those lands under other names, follow the landed code and say so in the report. Integer only in generation and simulation; floats only in the draw.

No new binding: Mine (the field's `.Dig`) held on a trunk fells it, as the Controls section says.

### Answers to what the item left open

1. **Entity or list: a list, generated, never stored.** A standing tree is a pure function of the world's recorded generation and its tree key; only the felled keys are state. Weighed against a machine of kind `tree` on a frame of its own per tree (0201's bare ground machine): the shipped density is about 4800 trees per km² (151 in a circle 200 m across), so a planet holds millions. As entities they would have to be created as the players walk (a creation queue every machine must run identically), saved (frames and pool entries per tree), hashed, and every frame loop walks them: `new_frame_cells_meet_a_frame` and `raycast_frames` try every frame ("frames and cells are few"), which a few thousand tree frames would break. As a list the save holds 12 bytes per felled tree, the hash covers the felled table only, and the aim, the walk and the placement checks ask the generation for the few trees in a box round the player.
2. **The model is a machine record of kind `tree`.** The species names a machine (`pine_tree`, kind `tree`, no item, footprint and `model` only), not a bare model id, so the tree's model loads, uploads, hot reloads and is checked and previewed by exactly the 0204 and 0207 pipeline (`load_machine_model_mesh`, `replace_machine_models`, `--model-check`, `--model-preview`, `records.machine_for_model`), with no second loader. The record is never an entity: `add_entity` refuses the kind. The item's "placeholder as the pod's" is superseded by the caller's ask: the model is a script of the 0204 kit.
3. **Placement: two jittered lattices on the sphere.** Groves are candidates of a coarse lattice, trees candidates of a fine one kept with a probability that falls off from the nearest grove's centre. A candidate is a hashed point in its lattice cube projected onto the sphere of the radius, kept only when the projection stays in the same cube, so every point of the sphere belongs to one key and no key is generated twice. Keys sit on the sphere of the radius, not on the relief, so a relief term never moves a key. No grid shows: points are jittered over the whole cube, groves are random discs of soft edge, and each tree has its own yaw, scale and shade.
4. **The trunk takes part in the overlap check.** A frame cell (a free foundation's, a snapped one's, a machine's on bare ground or on a frame) that meets a standing trunk refuses the placement with a new refusal `Tree_In_The_Way`, shown as the ghost's red as every refusal is. An old save whose frames stand where trees now generate has those trees cleared once at load (answer 9).
5. **Felling time:** `felling_milliseconds` per species, shipped 6000: four logs at the block world's 1.5 s per log block (`hardness_seconds` of `pine_log`), so a tree gives wood at the block world's rate. `PICK_UP_SECONDS` (0.6 s) would make wood nearly free. Divided by the cheat speed as hand mining is (`cheat_mining_ticks`).
6. **The yield:** the species' `item` and `count` (`log`, 4) go into the inventory whole, refused with `Inventory_Full` as a pick up is (no progress while they do not fit). `mined_from` of `log` stays the block world's list; the field's yield is the species' record.
7. **The crown** goes with the trunk: a felled tree is not drawn at all (no stump in this pass). The crown is neither collided nor aimed; the trunk's capsule is both.
8. **The clearing:** a record key `clearing_metres` (shipped 24), refused below the crater's reach (0199: radius + 6 × rim, shipped 18 m), so no tree stands in the crater or on its rim.
9. **Old saves:** a save without the felled table loads with no tree felled by a player; in `start_field_world` the trees whose trunk meets an occupied cell of any frame are added to the felled set once, with one log line, so no tree grows through an old pad. Question 1 below asks to confirm.
10. **Recorded as the relief is:** the placement keys and the species count go into `Planet_Generation_Record` (`trees`, `trees_recorded`); the species' machine, tint, item, count, felling time and trunk come from the data, the list repeated or cut to the recorded count as the palette is. A data edit of the placement never moves a saved world's trees.
11. **Draw:** trees within `FIELD_TREE_DRAW_METRES` (128 m) of the camera, at most `FIELD_TREE_DRAW_LIMIT` (256) per viewport, nearest first, one `DrawMesh` each (the body's lit layer; the model has no emissive layer), each grown in from scale 0 over the last 16 m so none pops. Machine models are drawn without the field's fog, so a fog fade is not available here. Expected load at the shipped density: about 250 trees within 128 m, about a third of them in the view frustum, so about 80 draw calls of 100 triangles a frame; the cap bounds a dense grove at 256 calls.

### Data

`data/planets.sjson`, the `home` planet gains (required key, comment per key):

```sjson
// Trees (work item 0197, doc/content.md, Trees): groves of trees on the
// surface above the sea, none in the home's clearing. A world records
// the placement keys and the species count in its world.sjson.
trees = {
	// The grove lattice's cube edge; a grove centre per cube at most.
	grove_spacing_metres = 40
	// The share of the grove cubes that hold a grove.
	grove_share_percent = 50
	// A grove's reach; the chance of a tree falls with the square of the
	// distance from its centre.
	grove_radius_metres = 14
	// The tree lattice's cube edge; a tree per cube at most.
	tree_spacing_metres = 4
	// The chance of a tree at a grove's centre.
	density_percent = 80
	// No tree within this of the home (the crater and its rim).
	clearing_metres = 24
	// No tree where the ground rises more than this per 100 m (35 degrees).
	maximum_slope_percent = 70
	species = [
		// machine: a machines.sjson record of kind tree, its model. tint
		// multiplies the model's colours. The yield is count of item after
		// Mine held felling_milliseconds on the trunk (four logs at the
		// block world's 1.5 s a log). The trunk is the capsule the walk,
		// the aim and the placements meet.
		{id = "pine", machine = "pine_tree", tint = [236, 232, 214], item = "log", count = 4, felling_milliseconds = 6000, trunk_radius_millimetres = 180, trunk_height_millimetres = 2500}
	]
}
```

Bounds (`trees_problem`, below), messages in the file's style `trees.<key> %d is outside %d to %d`:

| Key | Bounds | Shipped |
|---|---|---|
| `grove_share_percent` | 0 to 100; 0 is no trees and skips every other check, species may then be empty | 50 |
| `tree_spacing_metres` | `MINIMUM_TREE_SPACING_METRES` 2 to `MAXIMUM_TREE_SPACING_METRES` 16 | 4 |
| `grove_spacing_metres` | 2 × `tree_spacing_metres` to `MAXIMUM_GROVE_SPACING_METRES` 256 | 40 |
| `grove_radius_metres` | `tree_spacing_metres` to `grove_spacing_metres` (so a point's groves lie in the 27 grove cubes round it) | 14 |
| `density_percent` | 1 to 100 | 80 |
| `clearing_metres` | 0 to `MAXIMUM_TREE_CLEARING_METRES` 64, and at least the crater's reach when the crater is on (`trees.clearing_metres %d is inside the crater's reach of %d m`) | 24 |
| `maximum_slope_percent` | 1 to `MAXIMUM_TREE_SLOPE_PERCENT` 173 (60 degrees, the walkable angle of `data/game.sjson`) | 70 |
| `species` | 1 to `MAXIMUM_TREE_SPECIES` 8 entries | 1 |
| `species[i].id` | 1 to 32 bytes of `a-z0-9_`, unique | `pine` |
| `species[i].tint` | each 0 to 255 | `[236, 232, 214]` |
| `species[i].count` | 1 to `MAXIMUM_TREE_LOGS` 16 | 4 |
| `species[i].felling_milliseconds` | `MINIMUM_FELLING_MILLISECONDS` 100 to `MAXIMUM_FELLING_MILLISECONDS` 60000 | 6000 |
| `species[i].trunk_radius_millimetres` | 50 to 1000 | 180 |
| `species[i].trunk_height_millimetres` | 500 to 20000 | 2500 |
| `species[i].machine`, `item` | non-empty here; resolved by `planet_tree_species_problem` against the registries | `pine_tree`, `log` |

Expected count (`planet_tree_expected_count`, axis aligned lattices): groves per m² × trees per grove × circle area = (0.5 / 40²) × (0.8 × π 14² / 2 / 4²) × π 100² = 151 in a circle of 100 m radius. A lattice tilted against the axes keeps fewer candidates (down to about three quarters per lattice), so the planet's mean lies between about 0.56 and 1.0 of it.

`data/machines.sjson`: header line for the kind `tree`: "a tree's model (0197, doc/content.md, Trees): placed by the planet's generation, never by an item, never an entity; only `footprint` and `model` are read". New record after the pod:

```sjson
{
	id = "pine_tree"
	name_key = "machine_pine_tree"
	description_key = "describe_machine_pine_tree"
	kind = "tree"
	// The crown's reach in cells (2.6 of 3) and the model's height; the
	// model's bottom is the trunk's base, sunk 300 mm into the ground.
	footprint = {width = 6, depth = 6, height = 15}
	model = "pine_tree"
}
```

`data/strings/en.sjson`: `machine_pine_tree = "Pine"`, `describe_machine_pine_tree = "A tall conifer of the home planet. Mine held on the trunk fells it for four logs."`, `hint_fell = "Fell"`, `field_refused_tree_in_the_way = "A tree stands there"`.

`data/models/pine_tree.obj`, `pine_tree.mtl`: written by the kit (below), committed.

### Content types and checks (`data_planet.odin`, content cluster)

- `Planet_Tree_Species :: struct { id, machine: string, tint: [3]int, item: string, count, felling_milliseconds, trunk_radius_millimetres, trunk_height_millimetres: int }`.
- `Planet_Trees :: struct { grove_spacing_metres, grove_share_percent, grove_radius_metres, tree_spacing_metres, density_percent, clearing_metres, maximum_slope_percent: int, species: []Planet_Tree_Species }`, field `trees: Planet_Trees` on `Planet` after `crater`. Required: `missing_planet_key_problem` checks `trees` with `missing_struct_key(Planet_Trees, …)` (message `planets[%d].trees is missing %s`) and each species (`planets[%d].trees.species[%d] is missing %s`).
- `Planet_Tree_Placement :: struct { grove_spacing_metres, grove_share_percent, grove_radius_metres, tree_spacing_metres, density_percent, clearing_metres, maximum_slope_percent, species_count: int }`: what a world records.
- `planet_tree_placement :: proc(trees: Planet_Trees) -> Planet_Tree_Placement`: the seven keys and `len(species)`. Called by `planet_generation_record` and `resolve_world_planet`.
- `trees_problem :: proc(trees: Planet_Trees, crater: Planet_Crater) -> string`: the table above, in its order. Called by `planet_problem` after 0199's `crater_problem`. The crater's reach is 0199's (radius + `CRATER_RIM_FALL_PER_HEIGHT` × rim, zero for no crater); if 0199 lands a helper for it, call that.
- `tree_species_problem :: proc(species: Planet_Tree_Species, index: int) -> string`: the per species rows, called by `trees_problem`.
- `planet_tree_species_problem :: proc(planets: []Planet, items: Item_Registry, machines: Machine_Registry) -> string`: per planet, per species: `machine` is a machine of kind `.Tree` (`planets[%d].trees.species[%d].machine %q is not a machine of kind tree`), `item` an item (`… .item %q is not an item`). Called in `load_game_tables` (`data_reload.odin`) after `load_planets`, logged as `error: invalid planets.sjson: %s` with `return {}, {}, false`, as the torch check is.
- Constants: `MINIMUM_TREE_SPACING_METRES :: 2`, `MAXIMUM_TREE_SPACING_METRES :: 16`, `MAXIMUM_GROVE_SPACING_METRES :: 256`, `MAXIMUM_TREE_CLEARING_METRES :: 64`, `MAXIMUM_TREE_SLOPE_PERCENT :: 173`, `MAXIMUM_TREE_SPECIES :: 8`, `MAXIMUM_TREE_LOGS :: 16`, `MINIMUM_FELLING_MILLISECONDS :: 100`, `MAXIMUM_FELLING_MILLISECONDS :: 60_000`, `MINIMUM_TRUNK_RADIUS_MILLIMETRES :: 50`, `MAXIMUM_TRUNK_RADIUS_MILLIMETRES :: 1000`, `MINIMUM_TRUNK_HEIGHT_MILLIMETRES :: 500`, `MAXIMUM_TRUNK_HEIGHT_MILLIMETRES :: 20_000`.

`machine.odin`: `Machine_Kind` gains `Tree` after `Pod` (comment: a tree's model, 0197; never an entity), `machine_kind_names[.Tree] = "tree"`; the validation switch: `case .Tree:` refuses an item (`tree %q cannot be placed by an item`); `machine_kind_is_placed_by_world` includes `tree`. Every complete switch or enumerated array over `Machine_Kind` gets `.Tree` (the compiler names them; known: `fluid_machine_colors` in `render_fluids.odin` `{}`, `ui_machine.odin` lines 137 and 167 beside `.Pod`). `entity.odin` `add_entity`: `case .Tree: return NO_ENTITY` before the pool switch's end, so no path ever makes a tree an entity.

### The record (`generation_planet_record.odin`)

- `Planet_Generation_Record` gains `trees: Planet_Tree_Placement` and `trees_recorded: bool` after 0199's crater pair. `planet_generation_record` sets both (`planet_tree_placement(planet.trees)`, true).
- `make_recorded_planet`: when `record.trees_recorded`, `result.trees` takes the seven recorded keys and `species` repeated or cut to `record.trees.species_count` from the data's list (`make([]Planet_Tree_Species, count, allocator)`, entry `planet.trees.species[index % len]`; nil for a count of 0 or a data list of 0, which then also sets `grove_share_percent` to 0 so no tree generates without a species). `destroy_recorded_planet` deletes `trees.species`.
- `planet_generation_record_problem`: checks `species_count` 0 to `MAXIMUM_TREE_SPECIES` beside `palette_length`; the stand in planet gets `trees.species = {PLANET_TREE_STAND_IN_SPECIES}` (a valid species constant: `{id = "recorded", machine = "recorded", tint = {255, 255, 255}, item = "recorded", count = 1, felling_milliseconds = 1000, trunk_radius_millimetres = 100, trunk_height_millimetres = 1000}`), so a recorded placement passes `trees_problem`.
- `resolve_world_planet`: as the home and the crater, `if planet_generation_is_recorded(recorded) && !recorded.trees_recorded`: log `world: the world file records no trees, it takes the trees of %q from %s`, `record.trees, record.trees_recorded = planet_tree_placement(planet.trees), true`.
- `world.sjson` gains `trees` and `trees_recorded`; no format version step, no binary layout change.

### The generation (new file `src/generation_planet_trees.odin`, world cluster)

Header comment: answer 3, the rules below, "a pure function of the seed, the recorded planet and the key; the field spacing never moves a tree".

`generation_seed.odin`: `Generation_Purpose` gains `Planet_Groves` and `Planet_Trees`, appended last (comment: work item 0197), so no other seed changes.

Types:
```odin
Tree_Key :: [3]i32 // the tree lattice cube; unique per tree on the planet
Planet_Tree_Term :: struct {
	grove_seed, tree_seed: u64,
	spacing, grove_spacing, grove_radius, clearing: i64, // position units; spacing 0: no trees
	grove_share_percent, density_percent, maximum_slope_percent: i64,
	species_count: int,
	home: [3]i64, // the home on the sphere of the radius
}
Planet_Tree :: struct {
	key:           Tree_Key,
	base:          World_Position, // the trunk's bottom: the generated surface less PLANET_TREE_BASE_SINK_MILLIMETRES
	up:            [3]i64,         // unit radial
	yaw:           i32,            // angle units, from the north tangent towards its cross with up
	scale_percent: u8,             // 85 to 115
	shade_percent: u8,             // 92 to 108, the draw's brightness
	species:       u8,             // modulo species_count
}
```

`Planet_Generation` gains `trees: Planet_Tree_Term`, set in `make_planet_generation` by `make_planet_tree_term(seed, planet.trees, planet.home, radius)`.

Constants: `PLANET_TREE_SEA_MARGIN_METRES :: 1`, `PLANET_TREE_SLOPE_PROBE_METRES :: 1`, `PLANET_TREE_BASE_SINK_MILLIMETRES :: 300` (covers a 35 degree slope under a 207 mm trunk), `PLANET_TREE_MINIMUM_SCALE_PERCENT :: 85`, `PLANET_TREE_MAXIMUM_SCALE_PERCENT :: 115`, `PLANET_TREE_MINIMUM_SHADE_PERCENT :: 92`, `PLANET_TREE_MAXIMUM_SHADE_PERCENT :: 108`, `PLANET_TREE_JITTER_BITS :: 21`, `PLANET_TREE_BOX_CELL_LIMIT :: 1 << 20` (assert, a programming error past it).

Procedures (pure, integer, each 5 to 15 lines):
- `make_planet_tree_term :: proc(seed: u64, trees: Planet_Trees, home: Planet_Home, radius: i64) -> Planet_Tree_Term`: the zero term when `grove_share_percent == 0` or no species; else the lengths through `metres_to_position_units`, the seeds `derive_purpose_seeds(seed)[.Planet_Groves]` and `[.Planet_Trees]`, `home = fixed_scale(planet_home_direction(home), radius)`.
- `lattice_candidate :: proc(seed: u64, cell: [3]i64, spacing, radius: i64) -> (on_sphere: [3]i64, hash: u64, ok: bool)`: `hash = hash_lattice(seed, cell)`; per axis the jitter `i64(hash >> (axis * PLANET_TREE_JITTER_BITS) & (1 << PLANET_TREE_JITTER_BITS - 1)) * spacing >> PLANET_TREE_JITTER_BITS`; the point `cell * spacing + jitter`; not ok at the centre; `on_sphere` the point scaled to the radius (`project_onto_sphere` with `integer_square_root`); ok when `floor_divide_i64(on_sphere[axis], spacing) == cell[axis]` on every axis. Called for groves and trees alike.
- `cube_straddles_sphere :: proc(minimum, maximum: [3]i64, radius: i64) -> bool`: the nearest corner's squared distance at most radius² and the farthest's at least radius²; the cheap reject before `lattice_candidate`.
- `planet_groves_near :: proc(term: Planet_Tree_Term, radius: i64, minimum, maximum: [3]i64, allocator := context.temp_allocator) -> [][3]i64`: the grove centres of the grove cubes overlapping the box widened by `grove_radius`, those straddling the sphere, ok, and with `hash_combine(hash, 1) % 100 < grove_share_percent`.
- `grove_strength :: proc(groves: [][3]i64, grove_radius: i64, point: [3]i64) -> i64`: the largest `NOISE_ONE - d² * NOISE_ONE / r²` over groves within `r`, 0 for none.
- `planet_tree_slope_ok :: proc(generation: Planet_Generation, on_sphere, up: [3]i64) -> bool`: tangents `north := frame_north_tangent(up)`, `east := fixed_cross(north, up)`, `L := metres_to_position_units(PLANET_TREE_SLOPE_PROBE_METRES)`; `dn`, `de` the differences of `surface_relief` at `on_sphere ± fixed_scale(tangent, L)`; ok when `(dn² + de²) * 100² <= (2 L * maximum_slope_percent)²`.
- `planet_tree_from_candidate :: proc(generation: Planet_Generation, cell: [3]i64, on_sphere: [3]i64, hash: u64, strength: i64) -> (tree: Planet_Tree, ok: bool)`, in this order (cheapest first): kept when `hash_combine(hash, 1) % NOISE_ONE < strength * density_percent / 100`; outside the clearing (`|on_sphere - home|² > clearing²`); `relief := surface_relief(generation, on_sphere)` (with 0199's crater term) at least `generation.sea_radius - generation.radius + metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES)`; `up := normalize_fixed(on_sphere)`; `planet_tree_slope_ok`; then `base := World_Position(on_sphere + fixed_scale(up, relief - millimetres_to_position_units(PLANET_TREE_BASE_SINK_MILLIMETRES)))`, `yaw := i32(hash_to_range(hash_combine(hash, 2), 0, ANGLE_UNITS_PER_TURN - 1))`, `scale_percent` from `hash_combine(hash, 3)` in its range, `species := u8(hash_combine(hash, 4) % u64(species_count))`, `shade_percent` from `hash_combine(hash, 5)`.
- `planet_trees_in_box :: proc(generation: ^Planet_Generation, minimum, maximum: [3]i64, allocator := context.temp_allocator) -> [dynamic]Planet_Tree`: nothing for the zero term; the groves near the box once; then every tree cube of the box, x outermost, then y, then z, skipping cubes that do not straddle the sphere, each through `lattice_candidate`, `grove_strength` (skipped at 0) and `planet_tree_from_candidate`. The box is in position units on or near the sphere of the radius (callers project onto it).
- `planet_tree_at_key :: proc(generation: ^Planet_Generation, key: Tree_Key) -> (tree: Planet_Tree, found: bool)`: `planet_trees_in_box` over the key's cube alone.
- `planet_tree_box_round :: proc(generation: ^Planet_Generation, position: World_Position, reach: i64) -> (minimum, maximum: [3]i64)`: the position projected onto the sphere of the radius (`project_onto_sphere`), ± `reach` + one tree spacing on every axis. Used by every caller below.
- `tree_axes :: proc(up: [3]i64, yaw: i32) -> [3][3]i64`: right, up, forward; forward the north tangent turned by yaw towards `fixed_cross(north, up)` and projected (as `frame_forward` with any angle), right `normalize_fixed(fixed_cross(up, forward))` (as `frame_axes`). Used by the draw and its test.
- `tree_key_before :: proc(first, second: Tree_Key) -> bool`: x, then y, then z.
- `planet_tree_expected_count :: proc(trees: Planet_Trees, circle_radius_metres: int) -> int`: the axis aligned expectation above in integers (π as 355 / 113); for the test.

Cost: a 10 m box (the player's query) is 3 to 4 cubes an axis, of which about a third straddle the sphere; the groves near it are at most 8 cubes. A fine estimate is 20 to 60 µs per query; the implementer measures `planet_trees_in_box` for that box and for a 32 m region (the draw's) in a test log line (not a benchmark) and reports both.

### The simulation (new file `src/field_trees.odin`, simulation cluster)

Header comment: the felled set, the query round a player, the walk against the trunks, the aim, the felling, the placements against the trunks, the clearing of an old save, the save table.

Types and state:
- `Field_Tree_Species :: struct { machine: Machine_Id, tint: [3]u8, item: Item_Id, count: int, felling_ticks: u32, trunk_radius, trunk_height: i64 }` (lengths in position units).
- `Field_Content` gains `tree_species: []Field_Tree_Species`, made in `make_field_content` by `make_field_tree_species(planet.trees, items, machines, config.tick_rate, allocator)` (`felling_ticks = u32(max(felling_milliseconds * tick_rate / 1000, 1))`; an unresolved machine or item, possible only in code built test content, gives `NO_MACHINE` or `NO_ITEM`). A new `destroy_field_content :: proc(content: ^Field_Content)` deletes `brushes` and `tree_species`, and replaces the five `delete(... .brushes)` call sites (`benchmark_factory.odin` 580, `data_reload.odin` 366 and 369, `session.odin` 205 and 237).
- `Field_Tree_Target :: struct { hit: bool, key: Tree_Key, distance: i64 }`; `Field_Player` gains `tree_target: Field_Tree_Target` after `frame_target` (saved by name with the player; an old save reads it zero).
- `Mining_State` gains `tree: bool` (a felling's progress), so `mining_emitter` (`render_particles.odin`) returns false for it as it does for an entity.
- `Field_Simulation` gains `felled_trees: map[Tree_Key]struct{}` and `felled_trees_recorded: bool` (not saved; false while an old save's frames have not been cleared). `destroy_field_simulation` deletes the map.
- `Field_Placement_Kind` gains `Fell`; `Field_Placement` gains `tree: Tree_Key`.
- `Field_Edit_Refusal` gains `Tree_In_The_Way` (key `field_refused_tree_in_the_way`), and `field_edit_refusal_text` (`loop_planet_preview.odin`) the case `"  a tree stands there"`.
- Constants: `FIELD_TREE_QUERY_MARGIN_MILLIMETRES :: 1500` (the step of a tick, the capsule and the widest scaled trunk), `FIELD_TREE_AIM_STEP_MILLIMETRES :: 50`.

Procedures:
- `field_tree_species :: proc(content: Field_Content, tree: Planet_Tree) -> (species: Field_Tree_Species, found: bool)`: entry `species % len`; not found when the list is empty.
- `field_tree_trunk :: proc(tree: Planet_Tree, species: Field_Tree_Species) -> Field_Capsule`: bottom `base`, `up`, length and radius the species' times `scale_percent / 100`.
- `field_trees_near :: proc(field: ^Field_Simulation, position: World_Position, reach: i64) -> []Planet_Tree` (temp): `planet_trees_in_box` over `planet_tree_box_round(&field.world.water_planet.generation, position, reach)`, the felled dropped.
- `push_field_player_out_of_trunks :: proc(player: ^Field_Player, tuning: Field_Player_Tuning, trunks: []Field_Capsule)`: for each trunk whose span along its up overlaps the capsule's (feet height along `trunk.up` within `-capsule_height` to `trunk.length + capsule_radius`), the offset of the feet from the trunk's axis across `trunk.up`; when shorter than `trunk.radius + capsule_radius`, the feet move out along it by the shortfall and the velocity loses its part into the trunk; a zero offset pushes against `player.forward`. Integer, after the move.
- `field_trunk_ray_distance :: proc(trunk: Field_Capsule, eye: World_Position, look: [3]i64, limit: i64) -> (distance: i64, hit: bool)`: steps of `FIELD_TREE_AIM_STEP_MILLIMETRES` along the look up to `limit`; the first point with `field_distance_to_capsule_axis(trunk, point) <= trunk.radius`. Skips a trunk whose axis lies farther than `limit + radius` from the eye.
- `aim_field_player_at_trees :: proc(player: ^Field_Player, trees: []Planet_Tree, content: Field_Content)`: the nearest trunk hit within `field_aim_limit(player^, content.tuning)`; a hit sets `tree_target` and clears `target` and `frame_target` (the nearer wins, as `aim_field_player_at_frames`), otherwise `tree_target = {}`.
- `move_and_aim_field_player :: proc(field: ^Field_Simulation, frames: ^Frame_Table, content: Field_Content, player: ^Field_Player, input: Field_Player_Input)`: `trees := field_trees_near(field, player.position, tuning.reach + millimetres_to_position_units(FIELD_TREE_QUERY_MARGIN_MILLIMETRES))` once, `tick_field_player`, `push_field_player_out_of_trunks` (the trunks of `trees`), `aim_field_player_at_frames`, `aim_field_player_at_trees`. Replaces the `tick_field_player` and `aim_field_player_at_frames` pair in `queue_field_player_edit` (`field_mining.odin`) and in `predict_field_player_motion` (`lockstep.odin`), so the prediction walks into a trunk as the tick does.
- `field_aim_limit` (`simulation_field.odin`) also takes `min` with `tree_target.distance` when hit, so a torch behind a trunk is out of sight.
- `advance_field_felling :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, input: Field_Player_Input) -> (placement: Field_Placement, finished: bool)`: as `advance_field_pick_up`: Mine not held, no `tree_target` or the tree not found (`planet_tree_at_key`) or felled clears `player.mining`; the yield not fitting (`inventory_fits_all_picked_up` with `{item, count}`) clears it and sets `Inventory_Full`; else `advance_mining(player.mining, true, Raycast_Hit{hit = true, block = World_Coordinate(key), entity = NO_ENTITY}, AIR_BLOCK, cheat_mining_ticks(species.felling_ticks, state.cheat_speed))`, then `player.mining.tree = true`; finished gives `{kind = .Fell, tree = key}` and clears the progress.
- `queue_field_player_edit`: after the move, `if player.field.tree_target.hit` calls `advance_field_felling` (and appends a finished one) in place of `advance_field_pick_up`, so a held Mine on a trunk never clears or advances a pick up; `field_player_edit` digs nothing then, since the aim cleared `target`.
- `drain_field_felling :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, key: Tree_Key)`: in `drain_field_placements` for `.Fell`. Not found or already felled (another player this tick): nothing. The yield not fitting: `Inventory_Full`. Else `inventory_add_picked_up(player.inventory, content.items, species.item, species.count)` and `felled_trees[key] = {}`.
- `placement_cells_meet_a_trunk :: proc(state: ^Simulation_State, content: Simulation_Content, frame: Frame, cells: []World_Coordinate) -> bool`: the trees in the box round the cells' centres widened by the pitch and the tallest scaled trunk, any trunk meeting any cell through `frame_cell_meets_capsule`. Called with `.Tree_In_The_Way` in `field_placement_refusal` (a snapped machine, before `Would_Bury_Player`), `foundation_block_refusal` (after the frame checks of both branches) and `bare_ground_placement_refusal` (after `new_frame_cells_meet_a_frame`). The ghost goes red through the same refusals.
- `clear_trees_under_frames :: proc(state: ^Simulation_State, machines: Machine_Registry, field_content: Field_Content, generation: ^Planet_Generation) -> (cleared: int)`: per frame, its occupied cells (the live entities with `common.frame == frame.id`, `common_cells`), the trees in the box round them as above; a standing tree whose trunk meets one of them goes into `felled_trees`. Frames in table order, cells in pool order, so every machine clears the same keys.
- `start_field_world` (`session.odin`), after the water planet is set: when `plan.loading && !field.felled_trees_recorded`, `cleared := clear_trees_under_frames(...)`, log `save: written before trees (0197), no tree is felled; %d trees standing in frames cleared`, set recorded. `enable_new_field_world` sets `felled_trees_recorded = true`. `start_benchmark_field` and `lay_planet_preview_foundations` call `clear_trees_under_frames` after placing their pads (the benchmark's pad lies 24 m out, beyond the clearing), with the generation each already makes.
- The save: `Felled_Tree_Record :: struct { key: Tree_Key }`; `sorted_felled_tree_records :: proc(felled: map[Tree_Key]struct{}) -> []Felled_Tree_Record` (temp, `tree_key_before`); `write_felled_tree_table :: proc(bytes: ^[dynamic]byte, field: ^Field_Simulation)` (`write_list`), called in `write_simulation_state` after `write_machine_wear_table`; `read_felled_tree_table :: proc(reader: ^Byte_Reader, field: ^Field_Simulation) -> bool`, called in `read_simulation_state` after `read_machine_wear_table`: no bytes left leaves the map empty and `felled_trees_recorded` false (the log line is `start_field_world`'s); a list sets recorded true; a duplicate key is malformed (false). In entities.bin, so `simulation_state_hash` covers it with no change there.

### The HUD (`hud.odin`, ui cluster)

- `field_fell_hint_shown :: proc(screen_context: Screen_Context, hud: Hud_Context) -> bool`: the viewer's `tree_target.hit`. In the hint chain before `field_pick_up_hint_shown`: `{.Mine, text("hint_fell")}`, the inventory glyph, Pause. The felling's progress is the existing `draw_mining_progress` bar of `player.mining` (and the touch ring). No target status line for a tree in this pass.

### The draw (new file `src/render_field_trees.odin`, presentation cluster)

Constants: `FIELD_TREE_REGION_CELLS :: 8` (a region is 8 tree cubes an edge, 32 m at the shipped spacing), `FIELD_TREE_REGIONS_PER_FRAME :: 3`, `FIELD_TREE_DRAW_METRES :: 128`, `FIELD_TREE_GROW_IN_METRES :: 16`, `FIELD_TREE_DRAW_LIMIT :: 256`.

- `Field_Tree_Region :: [3]i32`; `Field_Tree_Cache :: struct { regions: map[Field_Tree_Region][dynamic]Planet_Tree }`; `Field_Renderer` gains `trees: Field_Tree_Cache`, destroyed in `destroy_field_renderer` (`destroy_field_tree_cache`).
- `field_tree_regions_around :: proc(generation: ^Planet_Generation, eyes: []World_Position, distance_metres: int) -> []Field_Tree_Region` (temp): the regions within the distance plus one region of any eye's point projected onto the sphere, straddling the sphere, sorted by the nearest eye's squared distance then `tree_key_before`.
- `update_field_tree_cache :: proc(cache: ^Field_Tree_Cache, generation: ^Planet_Generation, eyes: []World_Position)`: evicts regions not in the list, then generates up to `FIELD_TREE_REGIONS_PER_FRAME` missing ones nearest first (`planet_trees_in_box` over the region's cubes, kept in the cache's allocator). Called by `prepare_field_frame` (`loop_field_session.odin`) with the viewports' eyes, before any viewport draws, and by `stream_planet_preview` with the preview's eye. `field_viewport_eyes :: proc(state: ^Frame_State) -> []World_Position` is extracted from `field_viewport_selection`, which then calls it.
- `field_tree_cache_settled :: proc(cache: ^Field_Tree_Cache, generation: ^Planet_Generation, eyes: []World_Position) -> bool`: every listed region cached; the planet preview's screenshot also waits for it (`planet_preview_screenshot_due`'s `settled`).
- `tree_grow_factor :: proc(distance_metres: f32) -> f32`: 1 within `DRAW - GROW_IN`, falling to 0 at `DRAW`.
- `tree_render_matrix :: proc(tree: Planet_Tree, pitch_millimetres: int, grow: f32) -> matrix[4, 4]f32`: `tree_axes(tree.up, tree.yaw)` as columns scaled by the pitch in metres times `scale_percent / 100` times `grow`, the origin `world_position_to_metres(tree.base)` (as `frame_render_matrix`); the model's origin is its footprint's bottom centre.
- `Visible_Tree :: struct { tree: Planet_Tree, distance_squared: f32 }`; `field_visible_trees :: proc(cache: ^Field_Tree_Cache, felled: map[Tree_Key]struct{}, camera_metres: [3]f32, frustum: render_frustum.Frustum, extent_metres: f32) -> []Visible_Tree` (temp): not felled, within `FIELD_TREE_DRAW_METRES`, the box `base ± extent` in the frustum (`frustum_contains_box`); over the limit, sorted by distance and cut to `FIELD_TREE_DRAW_LIMIT`. `extent_metres` is the largest model's half footprint diagonal and top.
- `draw_field_trees :: proc(scene: Field_Scene, camera: rl.Camera3D)`: the frustum as `draw_field` makes it; per visible tree its species' model (`machine_model(scene.models, species.machine)`, skipped when none), the light `model_light_tint(with_light_level(0, .Sky, MAXIMUM_LIGHT), scene.frame.day_factor, scene.frame.sky_tint)` times `tint / 255` times `shade_percent / 100`, `draw_model_layers(scene.models, model.body, tree_render_matrix(tree, scene.content.field.foundation_pitch_millimetres, grow), light, {})`. Called in `draw_field_scene` right after `draw_entities`. The pitch is the content's foundation pitch, the unit 0207 previews models at.

### The model: `tools/models/machines/pine_tree.py` (0204 kit, 0207 entry)

- `tools/models/palette.py` gains `"bark": ((86, 62, 44), False)`, `"needles_dark": ((38, 70, 46), False)`, `"needles": ((50, 88, 56), False)`, `"needles_light": ((70, 108, 66), False)`, under a comment "Trees (0197)".
- `tools/models/machines/__init__.py`: `"pine_tree": pine_tree.build`.
- `pine_tree.py`: `build(machine)`. It reads the species whose `machine` is `machine.id` from `data/planets.sjson` and `foundation_pitch_millimetres` from `data/game.sjson` with 0207's `tools/sjson.py` (`sjson.load`; the data directory is `pathlib.Path(__file__).resolve().parents[3] / "data"`), `SystemExit` naming the machine when no species names it, so the trunk the walk meets is the trunk drawn. Cells are millimetres over the pitch (0.36 and 5.0 cells for the shipped trunk at 500 mm). Blender frame of the kit (x front, y = −game z, z up), all centred on (0, 0):
  1. Trunk, `bark`: `kit.cylinder((0, 0), 0.0, 12.0, trunk_radius_cells, 7, "bark")`, from the sunk base into the crown.
  2. Lower crown, `needles_dark`: `kit.cone((0, 0), 5.6, 11.0, 2.6, 0.8, 9, "needles_dark", rotation=0.0)`; its bottom is the trunk height plus the sink above the base (2.8 m, so 2.5 m over the ground and over the 1.8 m capsule).
  3. Middle crown, `needles`: `kit.cone((0, 0), 9.0, 13.4, 2.0, 0.5, 9, "needles", rotation=0.35)`.
  4. Top, `needles_light`: `kit.cone((0, 0), 12.0, 15.0, 1.2, 0.0, 7, "needles_light", rotation=0.8)`.
  5. `kit.join([...], "body")`. No part, no emissive material.
  Budget: about 100 triangles (trunk 24, the two frustums 32 each, the top 12), 4 materials: inside 0207's maxima (800, 8). The rotations are uneven so the cones' edges do not line up (No perceivable repetition); the per tree yaw does the rest.
- Generate with `tools/make_models.sh pine_tree` (which runs the model check), read `tools/model_preview.sh pine_tree` before handing back (both allowed to agents by 0207's approval; the planet preview stays forbidden).

### Tests (no GPU)

`src/generation_planet_trees_test.odin` (shipped planet from the test data directory, `DEFAULT_WORLD_SEED`, radius 8000 unless named):
- `test_the_same_seed_places_the_same_trees`: `planet_trees_in_box` over a 96 m box round the surface point 60 m from the home (bearing 0, `planet_direction_from_home`) twice gives equal lists, field by field, and at least 10 trees; the generations at spacings 1000, 500 and 333 (`TEST_FIELD_SPACINGS`) give the same list; seed + 1 gives a different list.
- `test_a_tree_key_regenerates_alone`: every tree of that box equals `planet_tree_at_key` of its key; a key of a cube with no tree is not found.
- `test_no_tree_stands_in_the_home_clearing`: a box of the clearing plus 40 m round the home: no tree's base projected onto the sphere lies within `clearing_metres` of `term.home`; at least one tree lies in the box (not vacuous); on the 4000, 8000 and 16000 m presets.
- `test_the_tree_density_stays_within_its_bounds`: 16 circle centres at latitudes −60, −20, 20, 60 and longitudes −135, −45, 45, 135; a circle counts when its centre's relief lies 2 m or more above the sea, at least 8 must; trees whose base projected onto the sphere lies within 100 m of the centre (a circle 200 m across). The mean count lies within 45 % to 110 % of `planet_tree_expected_count(trees, 100)` and no circle passes 3 times it. If the shipped data misses these bounds the implementer reports the numbers instead of widening them.
- `test_no_tree_stands_below_the_sea_or_on_a_steep_slope`: over those 16 circles every tree's relief at its key lies at least `PLANET_TREE_SEA_MARGIN_METRES` above the sea and `planet_tree_slope_ok` holds; a copy of the planet with `sea_level_metres = 8` places fewer trees in the same circles, none below its sea.
- `test_trees_stand_in_groves_not_on_a_grid`: in a 200 m box away from the home, the trees' offsets from their cube's corner take at least 16 distinct values per axis in centimetres, their yaws at least 16 distinct values, and the counts per 40 m sub box include an empty one and one with 5 or more.
- `test_tree_axes_turn_with_the_yaw`: `tree_axes` at a point gives orthonormal axes with the given up; yaw 0 points along `frame_north_tangent`, a quarter turn along `fixed_cross(north, up)`.
- `test_the_zero_tree_term_places_nothing`: a planet with `grove_share_percent = 0` (and the code built test planets) gives no trees in any box.

`src/data_planet_test.odin`:
- `test_a_tree_record_out_of_bounds_is_refused`: each key of the table one past each bound gives its message; the zero share with empty species passes; a clearing below the shipped crater's reach is refused; the shipped record passes.
- `test_a_tree_species_must_name_a_tree_model_and_an_item`: through `planet_tree_species_problem` with the shipped registries: an unknown machine, `stone_furnace` (another kind) and an unknown item each refused with the message; the shipped planets pass.

`src/generation_planet_record_test.odin`:
- `test_a_world_file_without_trees_takes_the_datas`: a record with `trees_recorded` false resolves to the data's placement; a recorded placement survives `make_recorded_planet` when the data's differs; a recorded `species_count` of 3 over a data list of 1 gives three entries of the one species; a count of 0 gives no trees.

`src/machine_test.odin`:
- `test_a_tree_machine_has_no_item_and_no_entity`: a `tree` record with an item is refused; `add_entity` of the shipped `pine_tree` returns `NO_ENTITY` and adds nothing.

`src/field_trees_test.odin` (field test sessions of `simulation_field_test.odin`; the tree is the nearest one to the home found by `planet_trees_in_box` in a 120 m box; the player stands 1.2 m from its trunk on the generated surface facing it, with the chunks round it staged as the existing walk tests stage them):
- `test_mine_held_fells_a_tree_for_its_logs`: Mine held: after `felling_ticks - 1` ticks no log and progress below 1 with `mining.tree` set; at `felling_ticks` four logs are in the inventory, the key is in `felled_trees`, the next tick's `tree_target` is clear and walking forward 3 s passes the trunk's place.
- `test_felling_is_refused_with_a_full_inventory`: every slot full of stone: no progress, `Inventory_Full` toasted once over 60 ticks, the tree stands.
- `test_a_felled_tree_stays_felled_after_a_save_and_load`: after the felling, the round trip of `test_a_field_world_save_round_trips`: `felled_trees` equal, `felled_trees_recorded` true, the state hash equal, `field_trees_near` round the tree does not return it.
- `test_two_sessions_fell_alike`: two sessions on one seed with the same inputs (the walk to the tree and the felling): `simulation_state_hash` equal every 30 ticks and at the end, and the hash differs from a third session that does not fell.
- `test_an_old_save_without_the_tree_table_loads_with_no_tree_felled`: a save of a field world with a free foundation placed at a tree's base (`place_free_foundation`), its encoded entities cut before the felled table (the last `write_list` of an empty map, 4 bytes): the load gives an empty set and `felled_trees_recorded` false; `clear_trees_under_frames` then clears exactly that tree (returns 1, key in the set) and a second tree 10 m off stands.
- `test_a_trunk_stops_the_walk`: walking 2 s straight at the trunk: the player's axis never comes nearer the trunk's axis than `trunk radius + capsule radius - FIELD_PENETRATION_TOLERANCE`; `predict_field_player_motion` on a copy gives the same position as the tick.
- `test_the_trunk_takes_the_aim`: facing the trunk at 1.2 m: `tree_target.hit`, distance within 60 mm of 1.2 m less the scaled radius, `target` and `frame_target` clear; turned 30 degrees aside: no `tree_target`.
- `test_a_placement_into_a_trunk_is_refused`: a free foundation aimed at the trunk's base, a 2 by 2 machine (stone furnace) on bare ground over it and a foundation snapped from a frame into the trunk's cell each give `Tree_In_The_Way`; the same 4 m away is allowed.

`src/render_field_trees_test.odin`:
- `test_the_tree_matrix_stands_the_model_on_its_base`: (0, 0, 0) maps to the base in metres, (0, 1, 0) to the base plus up times pitch times scale, within 1 mm; yaws 0 and a quarter turn map (1, 0, 0) a quarter turn apart.
- `test_trees_grow_in_at_the_draw_distance`: `tree_grow_factor` is 1 at 0 and 112 m, 0.5 at 120 m, 0 at 128 m and beyond.
- `test_the_tree_cache_fills_nearest_first_and_evicts`: one update adds at most `FIELD_TREE_REGIONS_PER_FRAME` regions, the eye's own first; enough updates settle it (`field_tree_cache_settled`); an eye 1 km away evicts every old region.
- `test_visible_trees_are_capped_nearest_first`: a cache with 300 trees in view gives 256, the nearest; a felled one and one past 128 m are left out.

`src/hud_test.odin` (beside the pick up hint tests): `test_the_fell_hint_shows_on_an_aimed_tree`: with `tree_target.hit` the glyph bar's Mine text is "Fell".

`src/model_triangle_mesh_test.odin` (0204's file): `test_the_shipped_tree_model_loads`: `pine_tree` resolves to its .obj and loads with an empty part and an empty emissive layer, at most 150 triangles, at most 4 materials; every vertex below 1 cell lies within 1.05 times the species' trunk radius in cells of the axis (the drawn trunk is the collided one). 0207's `test_the_shipped_models_pass_the_checks` covers the budget and the fit with no change.

Changed tests:
- 0196's `test_the_slice_recipe_chain_is_reachable_from_the_fields_yield`: the start set adds the items of the shipped planet's tree species; the assertion that no reachable recipe makes a log becomes: `log` is in the start set, and `plank`, `wooden_foundation` and `stone_cutting_table` are reachable from it.
- An existing field session test that now meets a tree outside the 24 m clearing (a refused placement, a walk blocked) takes a planet with `trees.grove_share_percent = 0` through a test helper `planet_without_trees`; the implementer lists each in the report.
- `test_the_pod_refuses_a_pick_up` (0199) and the benchmark test pass unchanged (the pod stands in the clearing, the benchmark's pad is cleared).

Verify commands: `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`, `tools/make_models.sh pine_tree` run twice with `cmp` of both files between the runs, `./build.sh model-check pine_tree`, `tools/model_preview.sh pine_tree` (read the 16 images). No benchmark, no session, no planet preview.

### Docs

- `doc/content.md`: a new section `## Trees` after Planets: the `trees` keys with bounds and shipped values, the species keys, the placement rules (the two lattices, the soft groves, the sea margin, the slope, the clearing at least the crater's reach), the expected count, the felling (Mine held `felling_milliseconds`, the yield, the refusals, the crown with the trunk), the model as a machine of kind `tree`. Planets: one line pointing to it. Items: `log` comes from the field's trees by the species' `item`; `mined_from` serves the block world. The Recipes or Foundations line of 0196 that the kit's planks are the only wood: replaced by the trees.
- `doc/content.md`, Models: the tree's script reads its trunk from its species in `planets.sjson` and the pitch from `game.sjson`.
- `doc/architecture.md`, World generation: the tree term (keys on the sphere of the radius, the same cube rule, groves, the rules, a pure function of the recorded planet, not of the spacing; `Planet_Groves` and `Planet_Trees` purposes). The field session: the state's `felled_trees`; the tick's query round each player, the walk against the trunks and the aim (`move_and_aim_field_player`, the prediction too), the felling (`advance_field_felling`, `.Fell` at the drain). Frames: `Tree_In_The_Way` in the three refusals; `clear_trees_under_frames` for an old save, the benchmark and the preview. Save format: the felled table after the wear table, an old save loading with none and the one log line; `world.sjson`'s `trees` and `trees_recorded`.
- `doc/presentation.md`, The field session: the scene's order gains the trees after the machines on frames; a bullet for the cache (regions of 8 cubes, 3 a frame nearest first, evicted past the distance), the draw distance, the cap, the grow in, the yaw, scale and shade per tree, the tint, the light of the open sky. Machine models: a record of kind `tree` holds a tree's model, drawn per tree by `draw_field_trees`.
- `doc/code_map.md`: `generation_planet_trees.odin` in world ("the trees on the sphere (0197): `Planet_Tree_Term` in `Planet_Generation`, `planet_trees_in_box`, `planet_tree_at_key`"), `field_trees.odin` in simulation ("the field's trees (0197): the felled set and its save table, the walk and aim against the trunks, the felling, the placements against the trunks"), `render_field_trees.odin` in presentation ("the trees' region cache and draw (0197)"); the `loop_field_session.odin` line names the trees in `draw_field_scene`; counts and "Reaches into" lines from `tools/code_graph.py`.
- `data/machines.sjson` header (kind `tree`), `data/planets.sjson` comments (above), `tools/models/palette.py` comment.
- `doc/log/<landing date>.md`, entry "Trees on the planet (0197)", tags `field, trees, generation, save, models, m14`: answers 1, 2, 4, 5, 9 and 10; the behaviour change for old saves (trees appear round an old world, those inside its frames are cleared at load, the wood is no longer the kit's alone).

### Hand-back lines that apply

- Memory a frame draws from: the tree cache's regions are freed and added only in `update_field_tree_cache`, which `prepare_field_frame` (and the preview's stream step) runs before any viewport draws, never inside the UI pass; `test_the_tree_cache_fills_nearest_first_and_evicts` reads the cache after the update as the draw does.
- A start-up load the game can make fail: a tree model that fails to load leaves the machines as boxes (`use_machine_models`), and `draw_field_trees` then skips the trees (no model found); a species naming no tree machine or no item refuses the data at load as every content check does.
- A number parsed from text is range checked: every `trees` key and species key by `trees_problem`, the recorded `species_count` by `planet_generation_record_problem`; the felling ticks are integer milliseconds times the tick rate.
- A changed save layout loads an old save: the felled table only appends (an old save loads with none, recorded false, one log line in `start_field_world`); `world.sjson` without `trees` takes the data's with one log line; the behaviour change (trees round an old world, those in its frames cleared) is named in the log; `test_an_old_save_without_the_tree_table_loads_with_no_tree_felled`.
- A list that grows without bound is capped where it draws: the drawn trees at `FIELD_TREE_DRAW_LIMIT`; the felled set grows with play (12 bytes a tree in the save) and is never drawn as a list.
- Tests never touch the machine's state directory: every new test works on in-memory sessions and encoded bytes.
- Not applicable: a file write (none new), a shared budget (none), a UI audit case made obsolete (none; the Fell hint is the pick up hint's sibling).

### Questions to the main agent

1. Old saves: confirm clearing the trees inside existing frames once at load (answer 9). The item's wording ("an old save loads with no tree felled") read literally would leave trunks standing through old pads.
2. Ground dug from under a tree: in this pass the tree stays at its generated height, standing on nothing. Keep that, or fell it with no yield when the field sample under its base turns to air (a check per tree in the query, simple, but it costs logs)?
3. The model as a machine record of kind `tree` (answer 2): confirm the reuse of the machine pipeline over a separate flora model path.
4. The felling time of 6 s (answer 5) against the item's "a few seconds".
5. The draw numbers (128 m, 256 trees, 3 regions a frame) are estimates from the density, not measurements; the phone's cost per `DrawMesh` is unmeasured. Measure on the couch and the phone after landing, or ask for a benchmark run in the window first?
6. Runs (belts and pipes) and torches are not checked against trunks in this pass: a run can pass through a trunk. Leave for a later item, or add the trunk test to the run tool's refusal now?

### Approval (main agent, 2026-10-03)

Approved as specified, with the answers: 1, yes, a tree standing inside an existing frame of an old save is felled once at load (no yield), named in the log. 2, changed: a tree does not float; when a field edit lowers the ground under a trunk's base by more than half the trunk's height below its generated base (checked in the edit's drain for the trees within the brush's reach plus the trunk radius, so every machine agrees), the tree is felled without yield, as if it fell into the hole; a test digs under a tree and finds it gone. 3, confirmed. 4, 6 seconds stand: four logs at the block world's rate, as the specification reasons. 5, the estimates stand; the couch and the phone judge. 6, runs are not checked against trunks in this pass; a later item if the couch finds one in the way.
