package game

// Cave schematics (work item 0036). World generation finds a crate site
// in some regions' cave pockets (generation_caves.odin); the main thread
// keeps the site when the chunk holding the crate cell loads, and the
// entity tick places the crate with its schematic. A schematic is a usable
// item: Use_Item on it (L2 with it selected) or Interact on a crate reads
// it, which consumes it and finds its schematic channel recipe.

SCHEMATIC_CRATE_SLOT_COUNT :: 1
SCHEMATIC_READ_KEY :: "schematic_read"

Schematic_Crate :: struct {
	using common: Entity_Common,
	slots:        [SCHEMATIC_CRATE_SLOT_COUNT]Item_Stack,
}

crate_site_known :: proc(crate_sites: []Crate_Site, region: Region_Coordinate) -> bool {
	for site in crate_sites {
		if site.region == region {
			return true
		}
	}
	return false
}

// Called on the main thread for every inserted chunk. A region's site is
// kept once, so a reloaded chunk never brings back a crate already placed.
register_crate_sites :: proc(crate_sites: ^[dynamic]Crate_Site, sites: []Crate_Site) {
	for site in sites {
		if !crate_site_known(crate_sites[:], site.region) {
			append(crate_sites, site)
		}
	}
}

// The schematic a site's choice picks among those the recipes name, or
// NO_ITEM when there are none.
schematic_for_choice :: proc(recipes: Recipe_Registry, choice: u64) -> Item_Id {
	items := schematic_items(recipes)
	if len(items) == 0 {
		return NO_ITEM
	}
	return items[choice % u64(len(items))]
}

// Crates of sites whose chunk is loaded. A site without a crate machine,
// without schematics or with an entity in its cell is marked placed
// without a crate, so it is not tried again.
place_pending_crates :: proc(world: ^World, crate_sites: []Crate_Site, content: Simulation_Content) {
	machine := find_machine_of_kind(content.machines, .Schematic_Crate)
	for &site in crate_sites {
		if site.placed || world_to_chunk_coordinate(site.position) not_in world.chunks {
			continue
		}
		site.placed = true
		schematic := schematic_for_choice(content.recipes, site.choice)
		if machine == NO_MACHINE || schematic == NO_ITEM || site.position in world.entities.cells {
			continue
		}
		handle := add_entity(&world.entities, content.machines, machine, site.position, 0)
		pool_get(&world.entities.schematic_crates, handle).slots[0] = Item_Stack{item = schematic, count = 1}
	}
}

// The selected hotbar item is used with Use_Item, which shares Place's
// control: a usable item never places, and anything else never uses.
// Interact on a schematic crate takes its schematic, and never jumps.
// Returns the input the rest of the tick sees and the item used, or
// NO_ITEM; the item is taken from the slot when its use consumes it
// (use_consumes_item). Like resolve_interact, it acts on the previous
// tick's target.
resolve_use_item :: proc(player: ^Player, entities: ^Entities, items: Item_Registry, input: Input_Frame) -> (result: Input_Frame, used: Item_Id) {
	result, used = input, NO_ITEM
	selected := &inventory_hotbar(player.inventory)[player.selected_hotbar_slot]
	if !stack_is_empty(selected^) && item_is_usable(items, selected.item) {
		result.pressed -= {.Place}
		result.just_pressed -= {.Place}
		if .Use_Item in input.just_pressed {
			used = selected.item
			if use_consumes_item(items.items[used].use, player.target.hit) {
				take_from_slot(selected, 1)
			}
		}
	} else {
		result.pressed -= {.Use_Item}
		result.just_pressed -= {.Use_Item}
	}
	if !schematic_crate_takes_interact(entities, player.target.entity) || .Interact not_in input.pressed {
		return
	}
	crate := pool_get(&entities.schematic_crates, player.target.entity)
	result.pressed -= {.Jump, .Interact}
	result.just_pressed -= {.Jump, .Interact}
	if .Interact in input.just_pressed && used == NO_ITEM && !stack_is_empty(crate.slots[0]) {
		used = crate.slots[0].item
		take_from_slot(&crate.slots[0], 1)
	}
	return
}

// Interact on a schematic crate takes its schematic, also on an empty
// one, where it does nothing but keeps A from jumping.
schematic_crate_takes_interact :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	return pool_get(&entities.schematic_crates, handle) != nil
}

// Reads a schematic: its recipe is found (counted once in the statistics)
// and the message log and a toast say so. Reading one found before only
// logs it again. Returns the recipe, or NO_RECIPE for an item that is no
// schematic.
read_schematic :: proc(unlocks: ^Recipe_Unlocks, quests: ^Quest_State, statistics: ^Statistics, recipes: Recipe_Registry, item: Item_Id, tick: u64) -> int {
	recipe := schematic_recipe_for(recipes, item)
	if recipe == NO_RECIPE {
		return NO_RECIPE
	}
	if record_found_schematic(unlocks, recipes, recipe) {
		statistics.schematics_found += 1
	}
	log_quest_message(quests, tick, SCHEMATIC_READ_KEY, recipes.recipes[recipe].name_key)
	return recipe
}
