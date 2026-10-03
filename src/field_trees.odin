package game

import "core:fmt"
import "core:slice"
import "platform"

// The field's trees (work item 0197, doc/architecture.md, The field
// session; doc/content.md, Trees). A standing tree is the generation's
// (generation_planet_trees.odin), never an entity: only the felled keys
// are state (Field_Simulation.felled_trees), saved in a table of their
// own at the end of entities.bin. Each tick queries the trees round each
// player once (move_and_aim_field_player): the walk is pushed out of the
// trunks, the aim takes the nearest trunk hit when it is nearer than the
// ground and the frames, and Mine held on a trunk fells it in the
// species' felling time (advance_field_felling), a placement the drain
// applies in order (drain_field_felling) for the species' logs. A frame
// cell that meets a trunk refuses a placement (Tree_In_The_Way). A dig
// that leaves the ground under a trunk's base hollow fells the tree
// without yield (fell_trees_over_dug_ground). A save written before the
// trees has the trees standing inside its frames felled once at load
// (clear_trees_under_frames).

// A tick's query reaches this far past the tool's reach: a tick's step,
// the capsule and the widest scaled trunk.
FIELD_TREE_QUERY_MARGIN_MILLIMETRES :: 1500
// The aim walks the look in steps of this.
FIELD_TREE_AIM_STEP_MILLIMETRES :: 50

// A species in the simulation's units: the machine holding its model, the
// tint, the yield, the felling time in ticks and the trunk in position
// units. NO_MACHINE or NO_ITEM only in code built test content.
Field_Tree_Species :: struct {
	machine:       Machine_Id,
	tint:          [3]u8,
	item:          Item_Id,
	count:         int,
	felling_ticks: u32,
	trunk_radius:  i64,
	trunk_height:  i64,
}

// The trunk under the reticle, nearer than the ground and the frames.
Field_Tree_Target :: struct {
	hit:      bool,
	key:      Tree_Key,
	// Along the look from the eye, in position units.
	distance: i64,
}

// In the save: one felled tree.
Felled_Tree_Record :: struct {
	key: Tree_Key,
}

make_field_tree_species :: proc(trees: Planet_Trees, items: Item_Registry, machines: Machine_Registry, tick_rate: int, allocator := context.allocator) -> []Field_Tree_Species {
	species := make([]Field_Tree_Species, len(trees.species), allocator)
	for &entry, index in species {
		source := trees.species[index]
		machine, machine_found := find_machine_id(machines, source.machine)
		item, item_found := find_item_id(items, source.item)
		entry = Field_Tree_Species {
			machine       = machine_found ? machine : NO_MACHINE,
			tint          = {u8(source.tint.r), u8(source.tint.g), u8(source.tint.b)},
			item          = item_found ? item : NO_ITEM,
			count         = source.count,
			felling_ticks = u32(max(source.felling_milliseconds * tick_rate / 1000, 1)),
			trunk_radius  = millimetres_to_position_units(source.trunk_radius_millimetres),
			trunk_height  = millimetres_to_position_units(source.trunk_height_millimetres),
		}
	}
	return species
}

// Each species names a machine of kind tree and an item (load_game_tables).
planet_tree_species_problem :: proc(planets: []Planet, items: Item_Registry, machines: Machine_Registry) -> string {
	for planet, planet_index in planets {
		for species, index in planet.trees.species {
			if machine, found := find_machine_id(machines, species.machine); !found || machines.machines[machine].kind != .Tree {
				return fmt.tprintf("planets[%d].trees.species[%d].machine %q is not a machine of kind tree", planet_index, index, species.machine)
			}
			if _, found := find_item_id(items, species.item); !found {
				return fmt.tprintf("planets[%d].trees.species[%d].item %q is not an item", planet_index, index, species.item)
			}
		}
	}
	return ""
}

// The tree's species; found is false without species.
field_tree_species :: proc(content: Field_Content, tree: Planet_Tree) -> (species: Field_Tree_Species, found: bool) {
	if len(content.tree_species) == 0 {
		return {}, false
	}
	return content.tree_species[int(tree.species) % len(content.tree_species)], true
}

// The trunk's capsule, scaled with the tree.
field_tree_trunk :: proc(tree: Planet_Tree, species: Field_Tree_Species) -> Field_Capsule {
	scale := i64(tree.scale_percent)
	return Field_Capsule{bottom = tree.base, up = tree.up, length = species.trunk_height * scale / 100, radius = species.trunk_radius * scale / 100}
}

// The generation the trees come from: the field world's planet.
field_tree_generation :: proc(field: ^Field_Simulation) -> ^Planet_Generation {
	return &field.world.water_planet.generation
}

// The standing trees round the position (temp allocator).
field_trees_near :: proc(field: ^Field_Simulation, position: World_Position, reach: i64) -> []Planet_Tree {
	generation := field_tree_generation(field)
	minimum, maximum := planet_tree_box_round(generation, position, reach)
	trees := planet_trees_in_box(generation, minimum, maximum)
	standing := make([dynamic]Planet_Tree, 0, len(trees), context.temp_allocator)
	for tree in trees {
		if tree.key not_in field.felled_trees {
			append(&standing, tree)
		}
	}
	return standing[:]
}

// The trunks of the trees with a species (temp allocator).
field_tree_trunks :: proc(trees: []Planet_Tree, content: Field_Content) -> []Field_Capsule {
	trunks := make([dynamic]Field_Capsule, 0, len(trees), context.temp_allocator)
	for tree in trees {
		if species, found := field_tree_species(content, tree); found {
			append(&trunks, field_tree_trunk(tree, species))
		}
	}
	return trunks[:]
}

// The walk.

// Each trunk whose span along its up overlaps the player's capsule moves
// the feet out across its up to the trunk's and the capsule's radii, and
// the velocity loses its part into the trunk; feet on the axis are pushed
// back against the forward. After the move; no clip passes.
push_field_player_out_of_trunks :: proc(player: ^Field_Player, tuning: Field_Player_Tuning, trunks: []Field_Capsule) {
	if player.no_clip {
		return
	}
	for trunk in trunks {
		offset := cast([3]i64)(player.position - trunk.bottom)
		along := fixed_dot(offset, trunk.up)
		if along < -tuning.capsule_height || along > trunk.length + tuning.capsule_radius {
			continue
		}
		across := offset - fixed_scale(trunk.up, along)
		distance := vector_length(across)
		needed := trunk.radius + tuning.capsule_radius
		if distance >= needed {
			continue
		}
		direction, ok := normalize_fixed(across)
		if !ok {
			direction, ok = normalize_fixed(project_onto_plane(-player.forward, trunk.up))
			if !ok {
				continue
			}
		}
		player.position += World_Position(fixed_scale(direction, needed - distance))
		if into := fixed_dot(player.velocity, direction); into < 0 {
			player.velocity -= fixed_scale(direction, into)
		}
	}
}

// The aim.

// The first step along the look within the limit whose point lies within
// the trunk's radius of its axis; a trunk whose axis lies past the limit
// and its radius is skipped.
field_trunk_ray_distance :: proc(trunk: Field_Capsule, eye: World_Position, look: [3]i64, limit: i64) -> (distance: i64, hit: bool) {
	if field_distance_to_capsule_axis(trunk, eye) > limit + trunk.radius {
		return 0, false
	}
	step := millimetres_to_position_units(FIELD_TREE_AIM_STEP_MILLIMETRES)
	for along: i64 = 0; along <= limit; along += step {
		if field_distance_to_capsule_axis(trunk, eye + World_Position(fixed_scale(look, along))) <= trunk.radius {
			return along, true
		}
	}
	return 0, false
}

// The nearest trunk the look meets before the ground, the frames and the
// reach (field_aim_limit, read before this tick's tree target) takes the
// aim and clears the other two targets; none clears the tree target.
aim_field_player_at_trees :: proc(player: ^Field_Player, trees: []Planet_Tree, content: Field_Content) {
	player.tree_target = {}
	limit := field_aim_limit(player^, content.tuning)
	eye := field_player_eye(player^, content.tuning)
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	best := Field_Tree_Target{distance = max(i64)}
	for tree in trees {
		species, found := field_tree_species(content, tree)
		if !found {
			continue
		}
		if distance, hit := field_trunk_ray_distance(field_tree_trunk(tree, species), eye, look, limit); hit && distance < best.distance {
			best = {hit = true, key = tree.key, distance = distance}
		}
	}
	if best.hit {
		player.tree_target = best
		player.target, player.frame_target = {}, {}
	}
}

// One field player's move and aim with the trees round it, queried once:
// the move, the push out of the trunks, the aim at the frames, then at
// the trunks. The tick (queue_field_player_edit) and the prediction
// (predict_field_player_motion) both run it, so the prediction walks into
// a trunk as the tick does.
move_and_aim_field_player :: proc(field: ^Field_Simulation, frames: ^Frame_Table, content: Field_Content, player: ^Field_Player, input: Field_Player_Input) {
	tuning := content.tuning
	trees := field_trees_near(field, player.position, tuning.reach + millimetres_to_position_units(FIELD_TREE_QUERY_MARGIN_MILLIMETRES))
	tick_field_player(&field.world, frames, tuning, player, input)
	push_field_player_out_of_trunks(player, tuning, field_tree_trunks(trees, content))
	aim_field_player_at_frames(player, frames, tuning)
	aim_field_player_at_trees(player, trees, content)
}

// The felling.

// The aimed standing tree and its species with a yield; found is false
// for none.
field_aimed_tree :: proc(state: ^Simulation_State, content: Simulation_Content, key: Tree_Key) -> (tree: Planet_Tree, species: Field_Tree_Species, found: bool) {
	if key in state.field.felled_trees {
		return {}, {}, false
	}
	tree = planet_tree_at_key(field_tree_generation(&state.field), key) or_return
	species = field_tree_species(content.field, tree) or_return
	return tree, species, species.item != NO_ITEM
}

field_tree_yield :: proc(species: Field_Tree_Species) -> [1]Item_Stack {
	return {{item = species.item, count = u16(species.count)}}
}

// Mine held on the aimed trunk advances the player's mining towards the
// species' felling time (divided under cheat speed, as hand mining), as
// advance_field_pick_up does for an entity; a finished one is the Fell
// placement. Mine released, the trunk gone or felled clears the progress;
// a yield the inventory cannot take clears it and tells Inventory_Full.
advance_field_felling :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, input: Field_Player_Input) -> (placement: Field_Placement, finished: bool) {
	target := player.field.tree_target
	_, species, found := field_aimed_tree(state, content, target.key)
	yield := field_tree_yield(species)
	switch {
	case .Dig not_in input.held || !target.hit || !found:
		player.mining = {}
		return {}, false
	case !inventory_fits_all_picked_up(player.inventory, content.items, yield[:]):
		player.mining = {}
		player.field_refusal = .Inventory_Full
		return {}, false
	}
	hit := Raycast_Hit{hit = true, block = World_Coordinate(target.key), entity = NO_ENTITY}
	player.mining, finished = advance_mining(player.mining, true, hit, AIR_BLOCK, cheat_mining_ticks(species.felling_ticks, state.cheat_speed))
	player.mining.tree = true
	if !finished {
		return {}, false
	}
	player.mining = {}
	return Field_Placement{kind = .Fell, tree = target.key}, true
}

// At the drain: the tree felled for its yield. Nothing for a tree gone or
// felled already (another player this tick); Inventory_Full when the
// yield does not fit, and the tree stands.
drain_field_felling :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, key: Tree_Key) {
	_, species, found := field_aimed_tree(state, content, key)
	if !found {
		return
	}
	yield := field_tree_yield(species)
	if !inventory_fits_all_picked_up(player.inventory, content.items, yield[:]) {
		player.field_refusal = .Inventory_Full
		return
	}
	inventory_add_picked_up(player.inventory, content.items, species.item, species.count)
	state.field.felled_trees[key] = {}
}

// A dig whose brush reaches a trunk or the ground under it (the brush's
// radius and the trunk's of its axis, the axis taken on down to the
// probe) and left the ground on the trunk's axis half the trunk's height
// below its base hollow fells the tree without yield, as if it fell into
// the hole. At the edit's drain, so every machine agrees; a probe in a
// chunk not loaded leaves the tree.
fell_trees_over_dug_ground :: proc(state: ^Simulation_State, content: Simulation_Content, edit: Field_Edit) {
	field := &state.field
	for tree in field_trees_near(field, edit.centre, edit.brush.radius + field_tree_widest_reach(content.field)) {
		species, found := field_tree_species(content.field, tree)
		if !found {
			continue
		}
		trunk := field_tree_trunk(tree, species)
		probe := trunk.bottom - World_Position(fixed_scale(trunk.up, trunk.length / 2))
		reached := Field_Capsule{bottom = probe, up = trunk.up, length = trunk.length + trunk.length / 2, radius = trunk.radius}
		if field_distance_to_capsule_axis(reached, edit.centre) > edit.brush.radius + trunk.radius {
			continue
		}
		sample := nearest_field_sample(probe, field.spacing_millimetres)
		if sample_to_field_chunk_coordinate(sample) not_in field.world.chunks {
			continue
		}
		if field_density_at(&field.world, field.spacing_millimetres, probe) <= 0 {
			field.felled_trees[tree.key] = {}
		}
	}
}

// The tallest and widest scaled trunk of the species: how far a cell or
// a brush must reach past a tree's key to meet its trunk.
field_tree_widest_reach :: proc(content: Field_Content) -> i64 {
	reach: i64 = 0
	for species in content.tree_species {
		reach = max(reach, (species.trunk_height + species.trunk_radius) * PLANET_TREE_MAXIMUM_SCALE_PERCENT / 100)
	}
	return reach
}

// The placements.

// The cells' centres' mean, and how far the farthest cell's centre lies
// from it.
frame_cells_centre :: proc(frame: Frame, cells: []World_Coordinate) -> (centre: World_Position, reach: i64) {
	sum: [3]i64
	for cell in cells {
		sum += cast([3]i64)frame_cell_centre(frame, cell)
	}
	centre = World_Position(sum / i64(max(len(cells), 1)))
	for cell in cells {
		reach = max(reach, vector_length(cast([3]i64)(frame_cell_centre(frame, cell) - centre)))
	}
	return centre, reach
}

// A standing trunk meets one of the cells (frame_cell_meets_capsule).
frame_cells_meet_a_trunk :: proc(field: ^Field_Simulation, content: Field_Content, frame: Frame, cells: []World_Coordinate) -> (tree: Planet_Tree, meets: bool) {
	if len(cells) == 0 {
		return {}, false
	}
	centre, reach := frame_cells_centre(frame, cells)
	for candidate in field_trees_near(field, centre, reach + frame_pitch_units(frame) + field_tree_widest_reach(content)) {
		species, found := field_tree_species(content, candidate)
		if !found {
			continue
		}
		trunk := field_tree_trunk(candidate, species)
		for cell in cells {
			if frame_cell_meets_capsule(frame, cell, trunk) {
				return candidate, true
			}
		}
	}
	return {}, false
}

// The placement refusals' trunk check (Tree_In_The_Way): a free
// foundation's, a snapped one's and a machine's cells, on bare ground or
// on a frame.
placement_cells_meet_a_trunk :: proc(state: ^Simulation_State, content: Simulation_Content, frame: Frame, cells: []World_Coordinate) -> bool {
	_, meets := frame_cells_meet_a_trunk(&state.field, content.field, frame, cells)
	return meets
}

// Every standing tree whose trunk meets an occupied cell of a frame goes
// into the felled set, without yield: an old save's frames (written
// before the trees), the benchmark's pad and the planet preview's. A set,
// so the order of the entities leaves the same keys on every machine.
// Returns the trees felled.
clear_trees_under_frames :: proc(state: ^Simulation_State, machines: Machine_Registry, field_content: Field_Content) -> (cleared: int) {
	entities := &state.world.entities
	for kind in Entity_Kind {
		for index in 0 ..< entity_pool_length(entities, kind) {
			common := entity_common_at(entities, kind, index)
			if common == nil || !common.alive || common.frame == BLOCK_FRAME {
				continue
			}
			frame, found := find_frame(&entities.frames, common.frame)
			if !found {
				continue
			}
			cells := common_cells(common^, machines)
			for {
				tree, meets := frame_cells_meet_a_trunk(&state.field, field_content, frame, cells)
				if !meets {
					break
				}
				state.field.felled_trees[tree.key] = {}
				cleared += 1
			}
		}
	}
	return cleared
}

// The save (entities.bin, after the machine wear table).

// In key order (temp allocator).
sorted_felled_tree_records :: proc(felled: map[Tree_Key]struct{}) -> []Felled_Tree_Record {
	records := make([dynamic]Felled_Tree_Record, 0, len(felled), context.temp_allocator)
	for key in felled {
		append(&records, Felled_Tree_Record{key = key})
	}
	slice.sort_by(records[:], proc(first, second: Felled_Tree_Record) -> bool {
		return tree_key_before(first.key, second.key)
	})
	return records[:]
}

// Always in a field world, so a save without it is one from before 0197
// (read_felled_tree_table).
write_felled_tree_table :: proc(bytes: ^[dynamic]byte, field: ^Field_Simulation) {
	write_list(bytes, sorted_felled_tree_records(field.felled_trees))
}

// A save from before 0197 ends before the table: no tree is felled and
// felled_trees_recorded stays false, so start_field_world clears the
// trees standing in its frames. False for a key listed twice.
read_felled_tree_table :: proc(reader: ^Byte_Reader, field: ^Field_Simulation) -> bool {
	clear(&field.felled_trees)
	field.felled_trees_recorded = false
	if bytes_left(reader^) == 0 {
		return true
	}
	records := make([dynamic]Felled_Tree_Record, context.temp_allocator)
	read_list(reader, &records) or_return
	for record in records {
		if record.key in field.felled_trees {
			return false
		}
		field.felled_trees[record.key] = {}
	}
	field.felled_trees_recorded = true
	return true
}

// At a load: a save written before the trees has the trees standing in
// its frames felled once, with one log line; then the set counts as
// recorded.
clear_trees_of_an_old_save :: proc(state: ^Simulation_State, machines: Machine_Registry, field_content: Field_Content) {
	if state.field.felled_trees_recorded {
		return
	}
	cleared := clear_trees_under_frames(state, machines, field_content)
	platform.log_printf("save: written before trees (0197), no tree is felled; %d trees standing in frames cleared", cleared)
	state.field.felled_trees_recorded = true
}
