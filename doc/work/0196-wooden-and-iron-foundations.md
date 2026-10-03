# 0196: Wooden, stone brick and iron foundations

Status: todo (user, 2026-10-03: "wooden foundation as the first step, and then iron foundation is the evolution, before automated tree farms arrive even later"; then "i like stone brick foundation as well, unlocked when we get stone cutting table (hand) and some stone cutting machine (automated), as a semi-early alternative to wood foundation"; after 0189)

## Goal

The pad's material tells the game's stage: wood at the start, stone brick once stone is cut, iron once a furnace runs, and wood again at scale when tree farms arrive (a later milestone). Today one `foundation` machine (`data/machines.sjson`, kind `foundation`, two stone bricks by hand, the bricks smelted in the furnace) is the only one, and the code assumes a single foundation (`content.field.foundation`, `field_foundation` in `entity_frames.odin`, the pod's pad and the benchmark's).

## Change

- Three machines of kind `foundation`, all one cell, each with its item: `wooden_foundation` (planks by hand; the plank recipe exists, four a log), `stone_brick_foundation` (the current one renamed, two stone bricks by hand; its item remapped in old saves, a log line) and `iron_foundation` (iron plates, hand or assembler). Every recipe is discovered as the design's channel says (`DESIGN.md`, Three progression channels): it appears the first time its ingredients are held, no technology.
- Stone is cut, not smelted: the `stone_brick` recipe leaves the furnace for two new machines, a `stone_cutting_table` (a hand station: planks and stone by hand; its panel offers the cutting recipes and the player crafts there, the bench of 0198 is the same kind of station) and a `stone_cutter` (automated, fuelled like the burner drill, slots and a panel as a crafting machine, an assembler kin for stone). So the stone brick foundation arrives semi early, after the table and before iron, and scales with the cutter.
- The held item decides which foundation a block places (0193); mixing on one frame is allowed. The benchmark's pad uses the one `game.sjson` names (`field.pad_foundation = "wooden_foundation"`); the pod has no pad (0199); the starting items give wooden foundations and planks for a first pad (`starting_items`, counts chosen so chapter 1's quests still hold; the quest that smelts stone bricks, if one does, moves to the table).
- The three share the foundation model with their own tint through the material weights, so a pad reads as wood, stone or iron at a glance; `doc/content.md` (Foundations: the three, the discovery, the pad's; Stone cutting: the table and the cutter), `doc/architecture.md` (the pad foundation of the content) updated.
- Until trees stand on the planet (0197) the only wood is the kit's; the log says so.

## Controls

- No control changes: the hotbar's selected item decides, as for any placed machine; the table's panel opens with the inventory binding (0194).

## Verify

- The build and check commands of 0168.
- Tests: each foundation places a block of its own kind; a mixed frame holds all three; an old save with the `foundation` item loads it as the stone brick one with the log line; the iron recipe is undiscovered until an iron plate is held and the stone brick one until a brick is; stone bricks are made at the table and the cutter and not in the furnace; the benchmark's pad is the content's pad foundation.
- The couch: the kit builds a wooden pad; the table cuts bricks for a stone pad; after the first iron plate the iron foundation appears.

## Specification (design, 2026-10-03)

Designed against `main` at 2411594. 0189 (in progress in the main checkout) touches `generation_planet*.odin` and `data_planet*.odin` only; nothing here overlaps it. 0198's bench and 0199's crater are not on `main`: the crafting station below is the kind 0198's `crafting_bench` will reuse, and the pod's pad keeps existing until 0199 removes it.

### Decisions on what the item left open

1. **One machine per tier, not one kind with a tier field.** Each item places at most one machine (`data/machines.sjson` header), the entity already stores its `Machine_Id`, and the drain already takes the item of `placement.machine` (`entity_frames.odin` lines 356, 382, 392, 487). Three records of kind `foundation` need no new entity field, no save field and no new tier enum; `machine_is_founded`, the pick up rules and the frame renderer all test the kind, so every tier founds, mixes on one frame and picks up the same.
2. **The tint comes from the machine record**: a new `color = [r, g, b]` key, required on kind `foundation`. `draw_frames` draws each foundation cell in its record's colour instead of `FRAME_FOUNDATION_COLOR`. Flat colour per tier with the existing seam (`FRAME_CELL_FILL`), no texture, so nothing tiles or stripes (`DESIGN.md`, no perceivable repetition: checked, a flat slab has no period). The item's "through the material weights" is read as "a per tier look on the shared slab"; see question Q1.
3. **Salvage (0201)**: `machine_wears` is false for kind `foundation`, so every foundation returns itself on pick up whatever the tier. The stone cutting table never counts an operation tick (it has no tick), so it always returns itself. A worn stone cutter returns 80 percent of its recipe's inputs rounded down: 0 stone furnace, 2 iron gears, 4 stone bricks.
4. **Old saves**: the old `foundation` item, machine and recipe load as `stone_brick_foundation` through a data driven rename (`former_ids`, below), with one log line. No save layout change: the remap is by id.
5. **The hand station** is a new machine kind `crafting_station` whose panel is the recipe browser filtered to the station's `recipe_maker`; crafts go into the player's hand queue. The station gates queuing only: `Craft_Command` is accepted for a recipe made by the station's maker while `Player.open_machine` is a live crafting station of that maker. A queued run keeps crafting after the panel closes, as any hand run does (`advance_crafting` never re-checks makers). Station recipes are planned as intermediates only from the station's panel. See Q2.
6. **The automated cutter** is an ordinary `crafting_machine` (burner, fixed recipe), so its panel, slots, inserters, wear and salvage are the existing ones.
7. **Discovery**: the three foundation recipes, the table and the cutter are `channel = "discovery"`, no technology (`DESIGN.md`, Three progression channels). `stone_brick` stays `start`: the table is its gate. No technology is added or changed.
8. **The pad foundation**: `field_simulation.pad_foundation = "wooden_foundation"` in `data/game.sjson` names the foundation of the benchmark's pad and, until 0199 removes it, the pod's pad of a new world. An old save's pod pad loads as stone brick (the rename); it stays placed by the world, since `field_entity_is_placed_by_world` tests the kind.
9. **The block size is per player, not per tier**: the three items share `foundation_size_index` and `foundation_height_index`; each item carries `configurable = "foundation_block"`.
10. **Chapter 1**: no quest smelts stone bricks, but the line quest places a belt, a belt run needs belt poles and a pole needs a stone brick, so the chapter now needs the table before the line. A quest `cutting` goes between `stock` and `line` to teach it. See Q3.
11. **Wood**: until 0197 the only wood is the kit's 8 planks: 4 build the table, 4 make 2 more wooden foundations. Written into the decision log.

### Data

`data/items.sjson` (header: document `former_ids`, see Save; prices follow "a crafted item about the sum of its inputs", stacks follow content.md Items: foundations are placed by the dozen, 100; table and cutter are machines, 50):

| id | category | stack_size | price | other |
| --- | --- | --- | --- | --- |
| `wooden_foundation` | machine | 100 | 2 (2 planks) | `configurable = "foundation_block"` |
| `stone_brick_foundation` | machine | 100 | 3 (kept from `foundation`) | `configurable = "foundation_block"`, `former_ids = ["foundation"]`; replaces the `foundation` entry in place |
| `iron_foundation` | machine | 100 | 2 (1 plate) | `configurable = "foundation_block"` |
| `stone_cutting_table` | machine | 50 | 8 (4 planks, 4 stone) | |
| `stone_cutter` | machine | 50 | 27 (furnace 5, gears 12, bricks 10) | |

Name and description keys by convention (`item_<id>`, `describe_item_<id>`).

`data/recipes.sjson` (header: add `stone_cutting` to the made_in list, document `former_ids`; craft times per content.md Recipes: logistics 0.5 s, machines 2 s):

- `stone_brick`: inputs stone 2, outputs stone_brick 1, `seconds = 1.6`, `made_in = ["stone_cutting"]`, category materials, tags `["stone"]` (drop `smelting`), channel start. 1.6 s keeps a hand pad cheap (two bricks in 3.2 s, the old furnace time for one) and puts the cutter at a furnace's pace (Ratio checks).
- `wooden_foundation`: plank 2 to 1, 0.5 s, `["hand", "assembler"]`, logistics, tags `["building", "wood"]`, discovery.
- `stone_brick_foundation`: replaces `foundation` in place, `former_ids = ["foundation"]`, stone_brick 2 to 1, 0.5 s, `["hand", "assembler"]`, logistics, tags `["building", "stone"]`, discovery (was start).
- `iron_foundation`: iron_plate 1 to 1, 0.5 s, `["hand", "assembler"]`, logistics, tags `["building", "iron"]`, discovery. One plate per cell makes iron the cheapest per raw unit (1 hematite against 4 stone or half a log), which is what makes it the evolution once drills feed furnaces.
- `stone_cutting_table`: plank 4 and stone 4 to 1, 2 s, `["hand", "assembler"]`, machines, tags `["stone", "wood"]`, discovery.
- `stone_cutter`: stone_furnace 1, iron_gear 3, stone_brick 5 to 1, 2 s, `["hand", "assembler"]`, machines, tags `["stone", "iron"]`, discovery. Priced near the burner drill (25), the other first burner machine.

`data/machines.sjson` (header: add `crafting_station` to the kind list with its rule, `color` on foundations, `former_ids`; order the three foundations wooden, stone brick, iron so `find_foundation_machine` returns wooden for the planet preview):

- `wooden_foundation`, `stone_brick_foundation` (`former_ids = ["foundation"]`, replaces `foundation`), `iron_foundation`: kind foundation, footprint 1 by 1 by 1, `color` `[150, 108, 66]`, `[150, 146, 138]` (today's `FRAME_FOUNDATION_COLOR`), `[104, 112, 122]`. Wood brown, stone light warm grey, iron darker blue grey: they differ in hue and brightness both.
- `stone_cutting_table`: kind `crafting_station`, footprint width 2, depth 1, height 2 (1 m by 0.5 m by 1 m at the 500 mm pitch), `recipe_maker = "stone_cutting"`, `model = "stone_cutting_table"`, no other keys.
- `stone_cutter`: kind crafting_machine, footprint 2 by 2 by 2, `speed = 0.5`, `fuel_slots = 1`, `fuel_power_kilowatts = 90`, `recipe_maker = "stone_cutting"`, `recipe_choice = "fixed"`, `input_slots = 1`, `output_slots = 1`, `model = "stone_cutter"`, `motion = {kind = "spin", axis = "z", amplitude = 1, period_seconds = 0.6, pivot = [1, 1.5, 1]}` (the blade; cadence follows the world, as every motion).

`data/game.sjson`: `starting_items` becomes stone_pickaxe 1, wooden_foundation 16, plank 8, torch 4 (comment: wooden foundations start a pad, the planks build the stone cutting table, no other wood until 0197). `field_simulation` gains `pad_foundation = "wooden_foundation"` (comment: the foundation of the benchmark's pad and of the pod's pad; must name a machine of kind foundation).

`data/dev_kits.sjson` (a developer jumping past chapter 1 can still make bricks and pads): chapter 2 adds stone_cutting_table 1 and wooden_foundation 50; chapter 3 adds stone_cutter 2 and stone_brick_foundation 100; chapters 4 to 8 add iron_foundation 100. Each kit stays under its 40 slots (header).

`data/quests/chapter_01.sjson`: a quest `cutting` between `stock` and `line`: objectives craft stone_cutting_table 1, place stone_cutting_table 1, craft stone_brick 2; `title_key = "quest_cutting_title"`, `text_key = "quest_cutting_text"`, `message_key = "mc_cutting"`. Header comment: the line's belt poles need bricks, cut at the table.

`data/strings/en.sjson`:

- Rename `item_foundation`, `describe_item_foundation`, `machine_foundation`, `describe_machine_foundation` to the `stone_brick_foundation` keys: "Stone brick foundation"; "Two stone bricks, a slab one cell thick. Placed free it starts a new grid along the ground; placed against another it joins that grid."
- `item_wooden_foundation` / `machine_wooden_foundation` "Wooden foundation"; describe: "Two planks, a slab one cell thick. The first pad, until stone is cut."
- `item_iron_foundation` / `machine_iron_foundation` "Iron foundation"; describe: "One iron plate, a slab one cell thick. Once the furnaces run, the cheapest floor there is."
- `item_stone_cutting_table` / `machine_stone_cutting_table` "Stone cutting table"; describe: "Four planks and four stone. Stone bricks are cut here by hand."
- `item_stone_cutter` / `machine_stone_cutter` "Stone cutter"; describe: "A burner saw that cuts stone into bricks from its input slot, as fast as a stone furnace smelts."
- `recipe_maker_stone_cutting = "Stone cutting"`.
- `describe_item_stone_brick`: "Two stone cut into one block at a stone cutting table or a stone cutter. Foundations, belt poles and the furnace linings."
- `describe_item_plank`: "Sawn timber, four from each log. Foundations, chests, pickaxes and sticks. Burns for 1 MJ if it comes to that."
- `quest_cutting_title = "Cut stone"`, `quest_cutting_text = "Build a stone cutting table, place it and cut two stone bricks at it."`, `mc_cutting` (Mission Control, one or two sentences in its voice: the belt poles of the line stand on bricks, and the bricks are cut, not fired).

### Code

Every signature below is new or changed; "callers" names every call site the change touches.

**Former ids (the rename), `save_remap.odin`, `item.odin`, `machine.odin`, `recipe.odin`, `data_reload.odin`, `save_world.odin`**

- `former_ids: []string` on `Item_Definition`, `Machine_Definition`, `Recipe_Definition` and on the records `Item`, `Machine`, `Recipe` (copied through in each resolve).
- `Content_Former_Id :: struct { former, current: string }` and `Content_Former_Ids :: [Content_Table][]Content_Former_Id`.
- `content_former_ids :: proc(content: Simulation_Content) -> Content_Former_Ids`: the items', machines' and recipes' former ids, temp allocator.
- `content_former_id_problem :: proc(content: Game_Content) -> string`: a former id that is also a current id of its table, or listed twice in one table, names the table and the id. Called in `load_content_registries` after the recipes load, logged as `error: invalid <file>: <problem>` like the others.
- `make_content_remap :: proc(saved, current: Content_Tables, former: Content_Former_Ids) -> Content_Remap`: a saved id missing from the current table but listed as a former id maps to that current id's index and is appended to `Content_Remap.renamed: [dynamic]Content_Renamed_Id` (`{table: Content_Table, former, current: string}`, temp allocator). Caller: `decode_entities` (save_world.odin:622), passing `content_former_ids(content)`; that one caller also serves the data reload.
- `renamed_content_line :: proc(remap: Content_Remap) -> string`: "" without renames, else `save: loaded under renamed ids: items foundation as stone_brick_foundation, machines foundation as stone_brick_foundation, recipes foundation as stone_brick_foundation` (table name from `content_table_names`, entries in table order then saved order). `decode_entities` logs it with `platform.log_printf` after a successful `read_simulation_state` when not "". One line per load.

**The foundation that Place puts down, `entity_frames.odin`, `simulation_field.odin`, `field_mining.odin`, `data_load.odin`, `entity_pod.odin`**

- `Field_Content.foundation` becomes `pad_foundation: Machine_Id` (the meaning changed: the content's pad foundation, not the one Place uses). `make_field_content` sets it with `find_machine_id(machines, config.field_simulation.pad_foundation)`, `NO_MACHINE` when absent.
- `Field_Simulation_Config` gains `pad_foundation: string`. `field_pad_foundation_problem :: proc(field: Field_Simulation_Config, machines: Machine_Registry) -> string`: not a machine, or not of kind foundation. Called in `load_game_tables` beside `field_torch_problem`, same log form.
- `field_foundation` becomes `field_pad_foundation :: proc(content: Simulation_Content) -> Machine_Id` (same body on `pad_foundation`). Callers: `benchmark_factory.odin` 549, `loop_planet_preview.odin` 531, `loop_planet_preview_runs.odin` 40, `simulation_field_test.odin` 221, 461, 768.
- `field_placed_machine`: the `.Foundation` case returns `player.held_machine` (in range, as the `.Machine` case), so the held item decides the tier. `field_tool_for_item` already sets `held_machine` for a foundation.
- `place_pod :: proc(entities: ^Entities, machines: Machine_Registry, pad_foundation: Machine_Id, surface_position: World_Position, heading: [3]i64, pitch_millimetres: int) -> (frame: Frame_Id, ok: bool)`: the pad of `pad_foundation`; refuses (`ok = false`) when it is `NO_MACHINE` or not of kind foundation. Callers: `enable_new_field_world` (passes `field_content.pad_foundation`), `entity_pod_test.odin` 20, 56, `entity_frames_test.odin` 648 (pass `find_foundation_machine(machines)`).
- Tests that set `content.field.foundation = find_foundation_machine(...)` set `pad_foundation` instead (field_mining_test 284, entity_frames_test 122, 200, 396, 485, 528, machine_wear_test 19, ui_audit_test 1264). Tests that place with `content.field.foundation` as the machine keep doing so through `pad_foundation`; the ones that hold the `"foundation"` item switch to `"stone_brick_foundation"` (or the wooden one; any foundation item works), `entity_frames_test.odin` 6 `test_machine(machines, "foundation")` likewise, `save_test.odin` 191, `item_test.odin` 30 (expect all three configurable), `field_mining_test.odin` 293 and 346, `machine_wear_test.odin` 334, `recipe_test.odin` 100 (rewritten, Tests).

**The slab colour, `machine.odin`, `render_frames.odin`, `render_entities.odin`**

- `Machine_Definition.color: [3]int`, `Machine.color: [3]u8`. `validate_machine_kind_fields`, `.Foundation` case: each channel 0 to 255 and not all zero (`foundation %q needs a color of three channels from 0 to 255`).
- `foundation_slab_color :: proc(machine: Machine) -> rl.Color` in `render_frames.odin`: the record's colour, alpha 255. `draw_frames` calls it per cell (`machines.machines[common.machine]`) in place of `FRAME_FOUNDATION_COLOR`, which stays for the pod's box fallback in `render_entities.odin`. Header comment of `render_frames.odin` updated.
- `render_entities.odin` 278: draw every entity of the foundations' pool whose machine kind is not `foundation` (the pod and the crafting stations), instead of `== .Pod`.

**Recipe maker and the crafting station kind, `recipe.odin`, `machine.odin`, `assembler.odin`, `entity.odin`, exhaustive switches**

- `Recipe_Maker` gains `Stone_Cutting` appended after `Recycler` (name `stone_cutting`), so the existing values keep their bits.
- `Machine_Kind` gains `Crafting_Station` appended after `Pod` (name `crafting_station`), with a doc comment: a place the player crafts at; its panel is the recipe browser filtered to its `recipe_maker`, its crafts run in the player's hand queue; it rides in the foundations' pool, an entity of its common data only, like the pod.
- `validate_crafting_station_definition :: proc(definition: Machine_Definition) -> string` (assembler.odin): `recipe_maker` parses and is not hand, furnace or recycler; no slots, fuel, electric power, speed or fluid ports; an item is required. Called from `validate_machine_kind_fields`.
- `crafting_station_recipes_problem :: proc(machines: Machine_Registry, recipes: Recipe_Registry) -> string`: a recipe made by a station's maker with fluid inputs or outputs is refused (the hand queue moves no fluid). Called in `load_content_registries` after `validate_crafting_machine_recipes`.
- `add_entity`: `case .Foundation, .Pod, .Crafting_Station:` into the foundations' pool.
- `entity_has_panel :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool`: a foundations' pool entity has a panel when its machine is a crafting station; everything else as today. Callers: `hud.odin` 479, `player.odin` 495 and 506, `simulation_field.odin` 291, `ui_audit_test.odin` 460, `schematic_test.odin` 259, `belt_placement_test.odin` 166, `entity_pod_test.odin` 44.
- Exhaustive `switch` over `Machine_Kind` gets the new case where the compiler asks: `machine_kind_names`, `validate_machine_kind_fields`, `ui_machine.odin` 137 and 167 (no area, beside `.Pod`), `render_fluids.odin` 55, `item_transfer.odin` 245 (beside `.Foundation`). `./build.sh check` lists any other.

**Hand crafting with makers, `crafting.odin`, `player_command.odin`, `ui_recipe_browser.odin`, `ui_recipes.odin`**

- `HAND_MAKERS :: Recipe_Makers{.Hand}`.
- `recipe_is_made_by :: proc(recipe: Recipe, makers: Recipe_Makers) -> bool`: `recipe.made_in & makers != {}`. `recipe_is_hand_craftable` stays (salvage uses it).
- `player_craft_makers :: proc(entities: ^Entities, machines: Machine_Registry, player: Player) -> Recipe_Makers`: `HAND_MAKERS`, plus the station's `recipe_maker` when `player.open_machine` is alive and its machine is a crafting station. Pure.
- `craft_refusal :: proc(recipe: Recipe, available: bool, makers: Recipe_Makers) -> Craft_Refusal`: `Not_Hand_Craftable` when `!recipe_is_made_by(recipe, makers)`.
- `Craft_Plan.makers: Recipe_Makers`; `make_craft_plan(..., makers := HAND_MAKERS)`; `hand_recipe_making(recipes, available, item, makers := HAND_MAKERS)` uses `recipe_is_made_by`; `plan_intermediate` passes `plan.makers`.
- A trailing `makers := HAND_MAKERS` on `plan_front_repair`, `plan_crafts`, `make_plan_after_queue`, `queue_crafts`, `plan_queue_crafts`, `queue_accepts_crafts`, `craftable_recipes`, `refresh_craftable_recipes`, `refresh_recipe_detail_plan`, `planned_input_states`, `planned_craft_count`; on `planned_crafts` it goes before `allocator` and its callers pass it explicitly. Each passes it down. Existing tests keep compiling with the default.
- `recipe_plan_key(queue, inventory, available, makers)`: the makers go into the hash, so the browser plans again between the inventory and a station.
- `apply_player_command`, `Craft_Command`: `queue_crafts(..., player_craft_makers(&state.world.entities, content.machines, player^))`. No command, network or save change.
- The UI side passes `player_craft_makers(&screen_context.world.entities, screen_context.machines, screen_context.player^)` in `queue_checked_crafts`, `refresh_craftable_recipes` and the detail plan of `recipe_screen`, so what the browser offers is what the tick accepts.

**The station's panel, `ui_recipes.odin`, `ui_machine.odin`**

- `Recipe_Browser.station: Entity_Handle` (NO_ENTITY in `make_recipe_browser`).
- `open_station_recipes :: proc(state: ^Ui_State, browser: ^Recipe_Browser, station: Entity_Handle)`: on the first frame sets `browser.station = station`, clears `filter.tags` and pushes `.Recipes`; when the recipe screen has been popped and the machine screen runs again with `browser.station == station`, clears it and pops the machine screen (so `close_slot_screens` queues the `Close_Machine_Command` as for any panel). Called at the top of `machine_screen` when the open machine's kind is `.Crafting_Station`, which returns after it.
- `station_filter :: proc(filter: Recipe_Filter, maker: Recipe_Maker) -> Recipe_Filter`: `makers = {maker}`, `available_only = true`, `craftable_only` kept. `recipe_screen` in station mode: no inventory tabs (as in selection), the title is the station machine's name (`text(machine.name_key)`), the filter is `station_filter`, the craft input and glyph bar are the normal crafting ones (`apply_recipe_craft_input`, `recipe_glyph_bar`, `recipe_touch_buttons(false)`). No binding changes: Open_Aimed (the inventory binding, 0194) opens it as any panel, Back closes it.

**Models, `tools/make_placeholder_models.py`, `data/models/`**

- `stone_cutting_table()`: over its footprint (width 2, depth 1, height 2): a plank top (`plank_texture`) on four legs, a stone block and a chisel on the top. `stone_cutter()`: 2 by 2 by 2, a grey stone body with a fire door (glow) at the front and a slot on the top, plus `stone_cutter_part` the round blade at the pivot. Added to `MODELS`; the script writes `stone_cutting_table.vox`, `stone_cutter.vox`, `stone_cutter_part.vox`. `model_mesh_test` needs no change (the station and the cutter have models).

### Save

No layout change. Old saves: item, machine and recipe `foundation` load as `stone_brick_foundation` by `former_ids`, and the load logs `save: loaded under renamed ids: items foundation as stone_brick_foundation, machines foundation as stone_brick_foundation, recipes foundation as stone_brick_foundation`. A saved craft queue run of the old recipe, a placed foundation, a held stack and the statistics all keep their meaning. Behaviour change for old saves: a furnace holding stone no longer makes bricks (its recipe left the furnace; the stone stays in the slot, no recipe matches); named in the log entry, and the dev kits of chapters 2 and 3 carry the table and the cutter.

### Tests

- `test_each_foundation_places_a_block_of_its_own_kind` (entity_frames_test): for each of the three items held in the hotbar (tool `.Foundation`), Place on a frame face drains into a foundation whose machine is that item's machine, and one item of that kind is taken; the other two kinds' counts are unchanged. Pitch 500.
- `test_a_mixed_frame_holds_all_three_foundations` (entity_frames_test): a wooden foundation placed free, a stone brick and an iron one snapped beside it on the same frame; all three on the frame; a 2 by 2 machine (stone furnace) on the stone brick and iron cells plus two more wooden ones is founded (`machine_is_founded`).
- `test_an_old_foundation_loads_as_the_stone_brick_foundation` (save_remap_test): a content copy whose stone brick foundation item, machine and recipe carry the id `foundation` and no former ids (the old build) writes a world with a placed foundation on a frame, a stack of 5 in the inventory and a craft run of the recipe; loading with the shipped content gives the machine, the stack and the run under `stone_brick_foundation`, and `renamed_content_line` returns the line above. Temporary directory.
- `test_a_former_id_that_is_also_an_id_is_refused` (save_remap_test): `content_former_id_problem` on registries where an item lists another item's id as a former id names both; a former id listed twice in one table is refused too; the shipped content passes.
- `test_foundation_recipes_are_discovered_by_their_ingredients` (recipe_test): fresh unlocks: none of the three foundation recipes available; obtaining plank, stone brick and iron plate makes each available in turn, and only its own.
- `test_stone_bricks_are_cut_not_smelted` (recipe_test): `furnace_recipe_for(stone) == NO_RECIPE`; the `stone_brick` recipe's `made_in == {.Stone_Cutting}`; `stone_cutting_table` is kind crafting_station and `stone_cutter` kind crafting_machine, both of maker stone_cutting.
- `test_a_crafting_station_lets_the_hand_queue_cut_stone` (crafting_test): a player with 4 stone and no open machine: a `Craft_Command` for `stone_brick` is refused; with `open_machine` a placed stone cutting table it queues, and after the recipe's ticks (96 at 60) twice the inventory holds 2 stone bricks; with 4 stone and the table open, queuing one `stone_brick_foundation` queues two `stone_brick` crafts ahead of it; with the inventory view's makers it is refused for want of bricks.
- `test_the_stone_cutter_cuts_bricks` (assembler_test): a stone cutter with a coal and 2 stone puts one stone brick into its output after 192 ticks (1.6 s at speed 0.5) and not at 191.
- `test_a_crafting_station_has_a_panel` (entity_test): `entity_has_panel` is true for a stone cutting table, false for a foundation, the pod and a belt pole.
- `test_the_pad_foundation_must_be_a_foundation` (simulation_field_test): `field_pad_foundation_problem` refuses an unknown id and `"stone_furnace"`, accepts the shipped `"wooden_foundation"`.
- `test_the_benchmark_pad_is_the_contents_pad_foundation` (benchmark_test): after `start_benchmark_field` every foundation on the benchmark's pad frame and the pod's pad has machine `content.field.pad_foundation`, whose id is `wooden_foundation`.
- `test_a_foundation_needs_a_colour` (machine_test): a foundation record without `color` or with a channel of 256 is refused; `foundation_slab_color` of the shipped three gives their three colours.
- `test_a_worn_stone_cutter_returns_its_inputs_share` (machine_wear_test): a stone cutter with `wear_ticks > 0` returns 2 iron gears and 4 stone bricks (`machine_return_stacks`), no furnace.
- Rewritten `test_the_slice_recipe_chain_is_reachable_from_the_fields_yield`: the start set is the materials' items plus `starting_items` of `data/game.sjson`; `slice_recipe_is_makeable` also accepts a recipe made by a station's maker once that station's item is held. Reachable: stone_furnace, wooden_foundation, stone_cutting_table, stone_brick, stone_brick_foundation, torch, belt_pole, burner_mining_drill, burner_inserter, belt, iron_chest, iron_foundation, stone_cutter; still not the wooden chest's way past the kit (assert the kit's 8 planks are the only plank source: no recipe reachable makes a log).
- UI audit (`ui_audit_test.odin`): `Ui_Audit_Case.station: Entity_Handle`, set like `selecting` in `audit_frame` (`views.recipe_browser.station`), and a case drawing the recipe screen in station mode at every audit size; `machines_with_panels` skips crafting stations (their machine screen only forwards).
- `test_shipped_quests_never_need_a_locked_recipe` covers the `cutting` quest unchanged.

### Docs

- `doc/content.md`: Recipes (the slice's chain: bricks cut at the table, the three foundations, the kit's planks; stations among the makers), Hand crafting (a crafting station adds its maker while its panel is open; station recipes plan as intermediates only there), Ratio checks (a stone cutter cuts 18.75 bricks a minute from 37.5 stone, a stone furnace's pace; 90 kW burns a coal in 44 s, 14 bricks), Foundations (three records, `color`, the held item decides, discovery, `pad_foundation`), a new section Stone cutting (the table, the cutter, the maker), Items (`former_ids`), Machines on bare ground (salvage line: foundations and stations return themselves).
- `doc/architecture.md`: The tick line ("a foundation item its foundation"), Frames (Foundations on the field: the held item's machine; the pod's pad and the benchmark's pad use `pad_foundation`), the save section (former ids in `make_content_remap`, the log line).
- `doc/presentation.md`: the scene line (foundations in their record's colour, `foundation_slab_color`), Machine models (the table, the cutter; the foundations' pool draws every non foundation entity).
- `doc/ui.md`: Recipe browser (station mode: title, filter, no tabs, back closes the station).
- `doc/quests.md`: chapter 1's `cutting` quest.
- `doc/log/2026-10-03.md`: the decisions (one machine per tier, the colour key, former ids, the station model gating queuing only, stone bricks out of the furnace, no wood but the kit's until 0197).
- Data file headers as listed under Data.

### Hand-back lines that apply

- A changed save layout loads an old save: there is no layout change; the rename is the remap, with one log line, tested by `test_an_old_foundation_loads_as_the_stone_brick_foundation`. The furnace no longer making bricks is named in the log entry and covered by the chapter 2 and 3 dev kits.
- A number parsed from text is range checked: `color` channels 0 to 255.
- A UI audit case a change makes obsolete is replaced: the station's recipe screen gets its own case; no case is lost.
- A new participant in a shared budget: the station's runs share the hand queue's `HAND_CRAFT_QUEUE_RUNS` and refuse with `Queue_Full` as any run; nothing else is shared.
- Tests never touch the machine's state directory: the save test uses a temporary directory.

### Verify

`./build.sh check`, `./build.sh check-android`, `./build.sh test`. A headless screenshot of a pad with the three tiers side by side (the screenshots memory).

### Questions to the main agent

- Q1: "their own tint through the material weights": read as a per tier flat colour on the record. If the user meant the terrain field's material textures (topsoil, stone weights of the field shader) on the slabs, the renderer seam changes to a textured slab per tier.
- Q2: the station gates queuing, not crafting: a run queued at the table finishes after the player walks off. The stricter reading (crafting pauses away from the table) needs the queue to know its station and a reach test in the tick.
- Q3: the new chapter 1 quest `cutting` (craft and place the table, cut 2 bricks). The alternative is no quest and a Mission Control hint, or a belt pole recipe without bricks.
- Q4: `stone_brick_foundation` moves from channel start to discovery (it appears with the first brick). An old save whose player never held a brick loses the recipe from the book until it does.
- Q5: iron at 1 plate a foundation is the cheapest tier per raw unit, on purpose; say if the evolution should cost more instead.

### Approval (main agent, 2026-10-03)

Approved as specified, with the answers: Q1, a flat colour per tier on the record; the slab's look is for the art pass of the model items, not this one. Q2, the table gates queuing only. Q3, the `cutting` quest goes in, short. Q4, discovery. Q5, changed: iron costs 2 plates a foundation (price 4), the same count as the other tiers, since the evolution is not the cheapest tier; wood is the bulk material once tree farms come. Everything else as written.
