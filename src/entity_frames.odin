package game

// Placement on foundation frames (work item 0174, doc/architecture.md,
// Frames). A foundation placed by snapping to a frame's cell joins that
// frame exactly; one placed free starts a new frame with its up along the
// radial at the hit and the yaw of the player's heading rounded to a
// twenty fourth of a turn. Two frames never merge, a frame never
// re-tangents, and the terrain under a frame is not changed. A machine on
// a frame occupies its footprint's cells, which must be free, and stands
// on solid occupants (a foundation) under its bottom cells; a foundation
// needs no support. The cells are integer triples, so the footprint, belt
// and lane logic of the block world runs on a frame unchanged.
//
// On the field the foundations, frames and machines are World.entities
// (0179), and a placement is a command queued in the player's tick and
// applied at the end of the tick in order, as the brush edits are
// (drain_field_placements). The hotbar's item decides what Place puts
// down (simulation_field.odin): a foundation snaps to a frame or starts
// one on the ground, any other machine snaps to a frame cell or stands on
// flat bare ground on a frame of its own (0201, machine_wear.odin),
// turned by the player's placement rotation. A foundation places a block of cells
// at once (0193, foundation_block_cells), its size and height chosen in
// the configure pop-up (0202) from the lists of data/game.sjson.

Frame_Placement_Refusal :: enum u8 {
	None,
	Unknown_Frame,
	// A footprint cell is taken.
	Occupied,
	// A bottom cell of a machine has no solid occupant under it.
	Unsupported,
	// A drill stands off every vein's disc (0179, place_drill_on_frame).
	No_Vein,
}

frame_placement_refusal :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, frame: Frame_Id, origin: World_Coordinate, rotation: u8) -> Frame_Placement_Refusal {
	if _, found := find_frame(&entities.frames, frame); !found {
		return .Unknown_Frame
	}
	definition := machines.machines[machine]
	for cell in footprint_cells(origin, definition.footprint, rotation) {
		if frame_cell_is_occupied(&entities.frames, frame, cell) {
			return .Occupied
		}
		if definition.kind != .Foundation && cell.y == origin.y && !frame_cell_is_solid(&entities.frames, frame, cell - UP) {
			return .Unsupported
		}
	}
	return .None
}

// A machine or a snapped foundation at origin in frame. A drill is
// refused: it enters only through place_drill_on_frame, which gives it
// its vein.
place_on_frame :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, frame: Frame_Id, origin: World_Coordinate, rotation: u8) -> (handle: Entity_Handle, refusal: Frame_Placement_Refusal) {
	if machines.machines[machine].kind == .Drill {
		return NO_ENTITY, .No_Vein
	}
	if refusal = frame_placement_refusal(entities, machines, machine, frame, origin, rotation); refusal != .None {
		return NO_ENTITY, refusal
	}
	return add_entity(entities, machines, machine, origin, rotation, frame), .None
}

// A foundation placed free: a new frame standing on the hit (free_frame_at)
// holding it at cell (0, 0, 0).
place_free_foundation :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, hit: World_Position, heading: [3]i64, pitch_millimetres: int) -> (handle: Entity_Handle, frame: Frame_Id) {
	origin, axes := free_frame_at(hit, heading, pitch_millimetres)
	frame = add_frame(&entities.frames, origin, axes, pitch_millimetres)
	return add_entity(entities, machines, machine, {}, 0, frame), frame
}

// The field content's pad foundation (the benchmark's pad and the pod's,
// work item 0196), NO_MACHINE when its machines have none (a content
// without machines, as the field tests make).
field_pad_foundation :: proc(content: Simulation_Content) -> Machine_Id {
	if int(content.field.pad_foundation) >= len(content.machines.machines) || content.machines.machines[content.field.pad_foundation].kind != .Foundation {
		return NO_MACHINE
	}
	return content.field.pad_foundation
}

// The machine Place puts on a frame with the held tool: the held
// foundation (its tier, 0196) or the held machine (0179); NO_MACHINE for
// any other tool.
field_placed_machine :: proc(player: Field_Player, content: Simulation_Content) -> Machine_Id {
	#partial switch player.tool {
	case .Foundation, .Machine:
		if int(player.held_machine) < len(content.machines.machines) {
			return player.held_machine
		}
	}
	return NO_MACHINE
}

// The first machine of kind foundation, NO_MACHINE when the data has none.
find_foundation_machine :: proc(machines: Machine_Registry) -> Machine_Id {
	for machine, index in machines.machines {
		if machine.kind == .Foundation {
			return Machine_Id(index)
		}
	}
	return NO_MACHINE
}

// Foundation blocks (0193).

// The entry at index: the first when the index is past the list (the
// data shrank since the save), one cell for an empty list.
foundation_block_entry :: proc(values: []int, index: u8) -> i32 {
	switch {
	case len(values) == 0:
		return 1
	case int(index) >= len(values):
		return i32(values[0])
	}
	return i32(values[index])
}

// A held foundation's block: size by size cells, height cells high.
field_foundation_block :: proc(player: Field_Player, field: Field_Content) -> (size, height: i32) {
	return foundation_block_entry(field.foundation_sizes, player.foundation_size_index), foundation_block_entry(field.foundation_heights, player.foundation_height_index)
}

// The first offset across a face for a side of side cells: centred on
// the anchor (the even side's extra cell on the high side, as the pod's
// pad, pod_pad_cells), or from the anchor upwards along the frame's up.
foundation_block_first_offset :: proc(side: i32, along_up: bool) -> i32 {
	return along_up ? 0 : -((side - 1) / 2)
}

// A foundation block's cells (doc/architecture.md, Frames): a square of
// size by size cells spans the face whose normal is given (zero reads as
// the frame's up), and the block runs height cells along the normal from
// the anchor. Across the face the square is centred on the anchor, but on
// a side face it rises from the anchor's row, so a wall stands on the
// pad's level instead of reaching into the ground. The order is fixed (by
// layer along the normal, then the face's second axis, then its first),
// so every machine adds the same entities in the same order. In the temp
// allocator.
foundation_block_cells :: proc(anchor, normal: World_Coordinate, size, height: i32) -> []World_Coordinate {
	axis, step := 1, i32(1)
	for index in 0 ..< 3 {
		if normal[index] != 0 {
			axis, step = index, normal[index] < 0 ? -1 : 1
		}
	}
	first_axis := axis == 0 ? 1 : 0
	second_axis := axis == 2 ? 1 : 2
	first_offset := foundation_block_first_offset(size, first_axis == 1)
	second_offset := foundation_block_first_offset(size, second_axis == 1)
	cells := make([dynamic]World_Coordinate, 0, int(size * size * height), context.temp_allocator)
	for layer in 0 ..< height {
		for second in 0 ..< size {
			for first in 0 ..< size {
				cell := anchor
				cell[axis] += step * layer
				cell[first_axis] += first_offset + first
				cell[second_axis] += second_offset + second
				append(&cells, cell)
			}
		}
	}
	return cells[:]
}

// A foundation placement's cells: the block from its cell away from the
// face hit, or a free one's from cell (0, 0, 0) of its new frame up.
field_placement_block_cells :: proc(placement: Field_Placement) -> []World_Coordinate {
	if placement.new_frame {
		return foundation_block_cells({}, UP, max(placement.size, 1), max(placement.height, 1))
	}
	return foundation_block_cells(placement.cell, placement.normal, max(placement.size, 1), max(placement.height, 1))
}

// The cells a placement fills, which its ghost draws: a foundation's
// block, any other machine's footprint at cell.
field_placement_cells :: proc(content: Simulation_Content, placement: Field_Placement, cell: World_Coordinate) -> []World_Coordinate {
	definition := content.machines.machines[placement.machine]
	if definition.kind == .Foundation {
		return field_placement_block_cells(placement)
	}
	return footprint_cells(cell, definition.footprint, placement.rotation)
}

// The field.

// A place command: a snapped placement names the frame and the cell, a
// free one the hit and the heading its new frame takes; a run (0176,
// belt_run_placement.odin) its two candidates instead; a torch and its
// removal (0179, simulation_field.odin) its sample; a pick up (0195,
// advance_field_pick_up) the frame and the cell held.
Field_Placement_Kind :: enum u8 {
	Machine,
	Run,
	Torch,
	Torch_Removal,
	Pick_Up,
}

Field_Placement :: struct {
	kind:      Field_Placement_Kind,
	run:       Field_Run_Placement,
	machine:   Machine_Id,
	// Quarter turns of a machine on its frame (0179).
	rotation:  u8,
	new_frame: bool,
	frame:     Frame_Id,
	cell:      World_Coordinate,
	// A foundation's block (0193, field_placement_block_cells): the
	// normal of the face hit (cell less the hit cell), the square's side
	// and the height in cells; zeros read as up and one.
	normal:    World_Coordinate,
	size:      i32,
	height:    i32,
	hit:       World_Position,
	heading:   [3]i64,
	sample:    Sample_Coordinate,
}

Queued_Field_Placement :: struct {
	player:    int,
	placement: Field_Placement,
}

// The frame target and the field target are both cast; the nearer stays
// and the other is cleared, so a brush never digs through a foundation.
// The frame ray passes a machine's open cells (0186), so the player
// aims out of the pod's door.
aim_field_player_at_frames :: proc(player: ^Field_Player, frames: ^Frame_Table, tuning: Field_Player_Tuning) {
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	player.frame_target = raycast_frames(frames, field_player_eye(player^, tuning), look, tuning.reach, excluded = {.Open})
	switch {
	case !player.frame_target.hit:
	case !player.target.hit || player.frame_target.distance <= player.target.distance:
		player.target = {}
	case:
		player.frame_target = {}
	}
}

// Where Place with a machine held puts it (field_placed_machine): against
// the targeted frame's face, or, for a foundation, free on the targeted
// ground. A machine other than a foundation on bare ground is
// field_bare_ground_placement's. A foundation takes the player's block
// (field_foundation_block).
field_player_placement :: proc(player: Field_Player, machine: Machine_Id, field: Field_Content) -> (placement: Field_Placement, wanted: bool) {
	size, height := field_foundation_block(player, field)
	switch {
	case machine == NO_MACHINE:
		return {}, false
	case player.frame_target.hit && player.tool == .Foundation:
		target := player.frame_target
		return Field_Placement{machine = machine, frame = target.frame, cell = target.adjacent, normal = target.adjacent - target.cell, size = size, height = height}, true
	case player.frame_target.hit:
		return Field_Placement{machine = machine, rotation = player.placement_rotation % 4, frame = player.frame_target.frame, cell = player.frame_target.adjacent}, true
	case player.target.hit && player.tool == .Foundation:
		return Field_Placement{machine = machine, new_frame = true, hit = player.target.position, heading = field_player_heading(player), size = size, height = height}, true
	}
	return {}, false
}

// A machine other than a foundation aimed at bare ground, no frame
// targeted (0187): a free placement on a new frame of its own (0201,
// machine_wear.odin), which the drain refuses with Too_Steep where the
// ground under the footprint is not flat enough
// (bare_ground_placement_refusal); the ghost is the machine's footprint
// at cell (0, 0, 0) of that frame, red when refused.
field_bare_ground_placement :: proc(player: Field_Player, machine: Machine_Id) -> (placement: Field_Placement, found: bool) {
	if machine == NO_MACHINE || player.tool == .Foundation || player.frame_target.hit || !player.target.hit {
		return {}, false
	}
	return Field_Placement{machine = machine, rotation = player.placement_rotation % 4, new_frame = true, hit = player.target.position, heading = field_player_heading(player)}, true
}

// The frame a placement lands in and its cell; for a free one the frame
// it would start, so the ghost draws where the foundation will be.
field_placement_frame :: proc(frames: ^Frame_Table, placement: Field_Placement, pitch_millimetres: int) -> (frame: Frame, cell: World_Coordinate, found: bool) {
	if placement.new_frame {
		origin, axes := free_frame_at(placement.hit, placement.heading, pitch_millimetres)
		return Frame{origin = origin, axes = axes, pitch_millimetres = pitch_millimetres}, {}, true
	}
	frame, found = find_frame(frames, placement.frame)
	return frame, placement.cell, found
}

// A cell whose box could reach into a player's capsule: its centre within
// the capsule's radius and half the cell's diagonal of the capsule's axis.
// Half the root of three, in ten thousandths, rounded up.
FRAME_CELL_HALF_DIAGONAL_TEN_THOUSANDTHS :: 8661

frame_cell_meets_capsule :: proc(frame: Frame, cell: World_Coordinate, capsule: Field_Capsule) -> bool {
	half_diagonal := frame_pitch_units(frame) * FRAME_CELL_HALF_DIAGONAL_TEN_THOUSANDTHS / 10000 + 1
	return field_distance_to_capsule_axis(capsule, frame_cell_centre(frame, cell)) < capsule.radius + half_diagonal
}

// A cell of a frame not yet made (a free foundation's, a machine's on
// bare ground, 0201) whose centre lies in an occupied cell of an existing
// frame: the new frame would stand inside the other's entities. Frames and
// cells are few, so every frame is tried.
new_frame_cells_meet_a_frame :: proc(table: ^Frame_Table, frame: Frame, cells: []World_Coordinate) -> bool {
	for cell in cells {
		centre := frame_cell_centre(frame, cell)
		for other in table.frames {
			if frame_cell_is_occupied(table, other.id, world_to_frame_cell(other, centre)) {
				return true
			}
		}
	}
	return false
}

field_placement_buries_a_player :: proc(state: ^Simulation_State, tuning: Field_Player_Tuning, frame: Frame, cell: World_Coordinate) -> bool {
	for player in state.players {
		if frame_cell_meets_capsule(frame, cell, field_player_capsule(tuning, player.field)) {
			return true
		}
	}
	return false
}

// Any of the footprint's cells (field_placement_buries_a_player).
field_footprint_buries_a_player :: proc(state: ^Simulation_State, content: Simulation_Content, frame: Frame, placement: Field_Placement, cell: World_Coordinate) -> bool {
	for footprint_cell in footprint_cells(cell, content.machines.machines[placement.machine].footprint, placement.rotation) {
		if field_placement_buries_a_player(state, content.field.tuning, frame, footprint_cell) {
			return true
		}
	}
	return false
}

// The frame's refusal of a snapped placement; a drill's also refuses a
// place off every vein (frame_drill_placement_refusal).
snapped_placement_refusal :: proc(state: ^Simulation_State, content: Simulation_Content, placement: Field_Placement) -> Frame_Placement_Refusal {
	entities := &state.world.entities
	if content.machines.machines[placement.machine].kind == .Drill {
		_, refusal := frame_drill_placement_refusal(entities, content.machines, state.world.veins[:], placement.machine, placement.frame, placement.cell, placement.rotation)
		return refusal
	}
	return frame_placement_refusal(entities, content.machines, placement.machine, placement.frame, placement.cell, placement.rotation)
}

// The refusal of a queued placement, None when it may go ahead.
field_placement_refusal :: proc(state: ^Simulation_State, content: Simulation_Content, player: Player, placement: Field_Placement) -> Field_Edit_Refusal {
	entities := &state.world.entities
	frame, cell, found := field_placement_frame(&entities.frames, placement, content.field.foundation_pitch_millimetres)
	if !found {
		return .Unknown_Frame
	}
	if placement.new_frame && content.machines.machines[placement.machine].kind != .Foundation {
		return bare_ground_placement_refusal(state, content, player, placement, frame)
	}
	if content.machines.machines[placement.machine].kind == .Foundation {
		return foundation_block_refusal(state, content, player, placement, frame)
	}
	if inventory_count(player.inventory, content.machines.machines[placement.machine].item) == 0 {
		return .Nothing_Held
	}
	if !placement.new_frame {
		#partial switch snapped_placement_refusal(state, content, placement) {
		case .None:
		case .No_Vein:
			return .No_Vein
		case:
			return .Frame_Cell_Taken
		}
	}
	if field_footprint_buries_a_player(state, content, frame, placement, cell) {
		return .Would_Bury_Player
	}
	return .None
}

// The counts a Too_Few_Foundations refusal of player names: the refused
// placement's cells and the foundations held (Field_Simulation.
// refused_foundation_counts).
record_refused_foundation_counts :: proc(state: ^Simulation_State, content: Simulation_Content, player: int, placement: Field_Placement) {
	counts := &state.field.refused_foundation_counts
	if len(counts) <= player {
		resize(counts, player + 1)
	}
	held := inventory_count(state.players[player].inventory, content.machines.machines[placement.machine].item)
	counts[player] = {len(field_placement_block_cells(placement)), held}
}

// A foundation block's refusal: the inventory must hold one foundation
// per cell, every cell must be free (the frame refusal of the first
// blocked one), and no cell may reach into a player.
foundation_block_refusal :: proc(state: ^Simulation_State, content: Simulation_Content, player: Player, placement: Field_Placement, frame: Frame) -> Field_Edit_Refusal {
	entities := &state.world.entities
	cells := field_placement_block_cells(placement)
	switch held := inventory_count(player.inventory, content.machines.machines[placement.machine].item); {
	case held == 0:
		return .Nothing_Held
	case held < len(cells):
		return .Too_Few_Foundations
	}
	if !placement.new_frame {
		for cell in cells {
			if frame_placement_refusal(entities, content.machines, placement.machine, placement.frame, cell, 0) != .None {
				return .Frame_Cell_Taken
			}
		}
	} else if new_frame_cells_meet_a_frame(&entities.frames, frame, cells) {
		return .Frame_Cell_Taken
	}
	for cell in cells {
		if field_placement_buries_a_player(state, content.field.tuning, frame, cell) {
			return .Would_Bury_Player
		}
	}
	return .None
}

// A foundation block that foundation_block_refusal let through, its cells
// in their fixed order; a free one starts its frame with cell (0, 0, 0).
// Returns the foundations placed.
apply_foundation_block :: proc(state: ^Simulation_State, content: Simulation_Content, placement: Field_Placement) -> int {
	entities := &state.world.entities
	frame := placement.frame
	if placement.new_frame {
		_, frame = place_free_foundation(entities, content.machines, placement.machine, placement.hit, placement.heading, content.field.foundation_pitch_millimetres)
	}
	cells := field_placement_block_cells(placement)
	for cell in cells {
		if !placement.new_frame || cell != {} {
			place_on_frame(entities, content.machines, placement.machine, frame, cell, 0)
		}
	}
	return len(cells)
}

// A queued placement that field_placement_refusal let through: a
// foundation block, a machine on bare ground on a frame of its own
// (0201), a drill with its vein, any other machine on its frame. Each
// placed machine counts for the quests (record_placed). Returns the
// machines placed, one item each.
apply_field_placement :: proc(state: ^Simulation_State, content: Simulation_Content, placement: Field_Placement) -> (placed: int) {
	entities := &state.world.entities
	placed = 1
	switch {
	case content.machines.machines[placement.machine].kind == .Foundation:
		placed = apply_foundation_block(state, content, placement)
	case placement.new_frame:
		place_on_bare_ground(state, content, placement)
	case content.machines.machines[placement.machine].kind == .Drill:
		place_drill_on_frame(entities, content.machines, state.world.veins[:], placement.machine, placement.frame, placement.cell, placement.rotation)
	case:
		place_on_frame(entities, content.machines, placement.machine, placement.frame, placement.cell, placement.rotation)
	}
	for _ in 0 ..< placed {
		record_placed(&state.records.statistics, placement.machine)
	}
	return
}

// The end of the tick, after the brush edits: every queued placement in
// order, each taking one item of its machine per machine placed (a
// foundation block one per cell); then the queue is empty.
drain_field_placements :: proc(state: ^Simulation_State, content: Simulation_Content) {
	for queued in state.field.placements {
		player := &state.players[queued.player]
		placement := queued.placement
		switch placement.kind {
		case .Run:
			drain_field_run_placement(state, content, player, placement.run)
			continue
		case .Torch:
			drain_field_torch(state, content, player, placement.sample)
			continue
		case .Torch_Removal:
			drain_field_torch_removal(state, content, player, placement.sample)
			continue
		case .Pick_Up:
			drain_field_pick_up(state, content, player, placement.frame, placement.cell)
			continue
		case .Machine:
		}
		if refusal := field_placement_refusal(state, content, player^, placement); refusal != .None {
			player.field_refusal, player.field_refused_material = refusal, .Air
			if refusal == .Too_Few_Foundations {
				record_refused_foundation_counts(state, content, queued.player, placement)
			}
			continue
		}
		placed := apply_field_placement(state, content, placement)
		inventory_remove(player.inventory, content.machines.machines[placement.machine].item, placed)
	}
	clear(&state.field.placements)
}

// Picking up (0195, doc/architecture.md, Frames). Mine held on a frame
// cell for PICK_UP_SECONDS takes the entity in it, as the block world's
// mine_entity does; one entity per hold, so a foundation block goes cell
// by cell. The hold advances in the player's tick (advance_field_pick_up)
// and a finished one is a placement command, applied at the drain in
// order with the others, so the drain checks it again against the world
// the commands before it left.

// The pod and the foundations of its pad: no hint, no progress and no
// refusal told, as the block world's capsule.
field_entity_is_placed_by_world :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	common := entity_common(entities, handle)
	if common == nil || machines.machines[common.machine].item == NO_ITEM {
		return true
	}
	return machines.machines[common.machine].kind == .Foundation && cell_is_on_pod_pad(common.origin) && frame_holds_pod(entities, machines, common.frame)
}

frame_holds_pod :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id) -> bool {
	for foundation in entities.foundations.entries {
		if foundation.alive && foundation.frame == frame && machines.machines[foundation.machine].kind == .Pod {
			return true
		}
	}
	return false
}

// The pad's cells of place_pod: pod_pad_cells and cell (0, 0, 0).
cell_is_on_pod_pad :: proc(cell: World_Coordinate) -> bool {
	first, last := i32(POD_PAD_FIRST_CELL), i32(POD_PAD_FIRST_CELL + POD_PAD_SIZE - 1)
	return cell.y == 0 && cell.x >= first && cell.x <= last && cell.z >= first && cell.z <= last
}

// A machine other than a foundation (which needs no support) stands in
// the cell.
frame_cell_holds_machine :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id, cell: World_Coordinate) -> bool {
	common := entity_common(entities, entity_at(entities, cell, frame))
	return common != nil && machines.machines[common.machine].kind != .Foundation
}

// A belt or pipe run ends in the cell (a pole's or a belt end's cell).
frame_cell_holds_run_end :: proc(entities: ^Entities, frame: Frame_Id, cell: World_Coordinate) -> bool {
	for run in entities.belt_runs.entries {
		if !run.alive {
			continue
		}
		for endpoint in run.endpoints {
			if endpoint.frame == frame && endpoint.cell == cell {
				return true
			}
		}
	}
	return false
}

// A torch's sample lies in the cell.
frame_cell_holds_torch :: proc(torches: []Field_Torch, frame: Frame, cell: World_Coordinate, spacing_millimetres: int) -> bool {
	for torch in torches {
		if world_to_frame_cell(frame, sample_to_world_position(torch.sample, spacing_millimetres)) == cell {
			return true
		}
	}
	return false
}

// A run starts or ends at the pole; removing the pole would remove the
// run and the items on it (remove_belt_runs_on_pole).
pole_holds_run :: proc(entities: ^Entities, pole: Entity_Handle) -> bool {
	for run in entities.belt_runs.entries {
		if run.alive && (run.endpoints[BELT_RUN_START].pole == pole || run.endpoints[BELT_RUN_END].pole == pole) {
			return true
		}
	}
	return false
}

// Something stands on the entity or hangs from it: in a cell right above
// one of its cells, a machine other than a foundation, a run's end or a
// torch, or for a pole a run on it. Taking the entity would leave it in
// the air or lose the run silently; the player takes those first.
field_entity_is_held_up :: proc(state: ^Simulation_State, content: Simulation_Content, handle: Entity_Handle) -> bool {
	entities := &state.world.entities
	common := entity_common(entities, handle)
	if common == nil {
		return false
	}
	if handle.kind == .Belt_Pole && pole_holds_run(entities, handle) {
		return true
	}
	frame, found := find_frame(&entities.frames, common.frame)
	if !found {
		return false
	}
	for cell in common_cells(common^, content.machines) {
		above := cell + UP
		if entity_at(entities, above, frame.id) == handle {
			continue
		}
		if frame_cell_holds_machine(entities, content.machines, frame.id, above) || frame_cell_holds_run_end(entities, frame.id, above) || frame_cell_holds_torch(state.field.torches[:], frame, above, state.field.spacing_millimetres) {
			return true
		}
	}
	return false
}

// Mine held on a frame cell advances the player's mining towards
// PICK_UP_SECONDS (advance_mining, keyed on the entity's origin as the
// block world's mine_entity); a finished hold is the pick up command. An
// entity placed by the world gets no progress; one held up gets none and
// tells Something_Stands_On_It, one the inventory has no room for gets
// none and tells Inventory_Full, every tick, so a held Mine toasts once
// (field_refusal_is_news). The drain checks both again. Mine released or aimed off a frame
// clears the progress. The prediction (0182) never runs this, so the
// progress the HUD draws is the confirmed tick's.
advance_field_pick_up :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, input: Field_Player_Input) -> (placement: Field_Placement, finished: bool) {
	target := player.field.frame_target
	entities := &state.world.entities
	handle := entity_from_occupant(target.occupant.handle)
	switch {
	case .Dig not_in input.held || !target.hit || field_entity_is_placed_by_world(entities, content.machines, handle):
		player.mining = {}
		return {}, false
	case field_entity_is_held_up(state, content, handle):
		player.mining = {}
		player.field_refusal = .Something_Stands_On_It
		return {}, false
	case !inventory_fits_all_picked_up(player.inventory, content.items, entity_pickup_stacks(&state.world, content, handle)):
		player.mining = {}
		player.field_refusal = .Inventory_Full
		return {}, false
	}
	hit := Raycast_Hit{hit = true, block = entity_common(entities, handle).origin, entity = handle}
	player.mining, finished = advance_mining(player.mining, true, hit, AIR_BLOCK, mining_required_ticks(PICK_UP_SECONDS, state.tick_rate))
	if !finished {
		return {}, false
	}
	player.mining = {}
	return Field_Placement{kind = .Pick_Up, frame = target.frame, cell = target.cell}, true
}

// At the drain: the entity in the cell taken whole into the inventory
// with its contents (take_entity_into_inventory); its frame goes with its
// last cell (release_empty_frame). Refused when it holds something up, or
// when the inventory cannot take everything, since the field has no
// loose items to spill: the entity stays and Inventory_Full is told.
drain_field_pick_up :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, frame: Frame_Id, cell: World_Coordinate) {
	entities := &state.world.entities
	handle := entity_at(entities, cell, frame)
	switch {
	case field_entity_is_placed_by_world(entities, content.machines, handle):
		return
	case field_entity_is_held_up(state, content, handle):
		player.field_refusal = .Something_Stands_On_It
		return
	case !inventory_fits_all_picked_up(player.inventory, content.items, entity_pickup_stacks(&state.world, content, handle)):
		player.field_refusal = .Inventory_Full
		return
	}
	take_entity_into_inventory(&state.world, &state.records.statistics, content, player.inventory, handle)
}

// The save (save_state.odin, write_later_tables).

// An entity off the block frame; Entity_Common.frame is left out of the
// pools' bytes.
Entity_Frame_Record :: struct {
	handle: Entity_Handle,
	frame:  Frame_Id,
}

// Every live entity off frame 0, in pool order. The belt poles' frames
// are saved with their pool after these tables (write_belt_run_tables).
entity_frame_records :: proc(entities: ^Entities) -> []Entity_Frame_Record {
	records := make([dynamic]Entity_Frame_Record, context.temp_allocator)
	for kind in Entity_Kind {
		if kind == .Belt_Pole {
			continue
		}
		for index in 0 ..< entity_pool_length(entities, kind) {
			common := entity_common_at(entities, kind, index)
			if common != nil && common.alive && common.frame != BLOCK_FRAME {
				append(&records, Entity_Frame_Record{handle = common.handle, frame = common.frame})
			}
		}
	}
	return records[:]
}

// The foundations, the frame records, the frame id counter and the
// entities off frame 0, then the belt poles and runs (0176,
// write_belt_run_tables). A world that never had a frame, a foundation, a
// pole or a run writes nothing, so its bytes and its state hash are those
// of a build before frames, unless always (a field world, whose field
// tables follow) asks for them.
write_frame_tables :: proc(bytes: ^[dynamic]byte, entities: ^Entities, always := false) {
	if !always && len(entities.frames.frames) == 0 && len(entities.foundations.entries) == 0 && len(entities.belt_poles.entries) == 0 && len(entities.belt_runs.entries) == 0 {
		return
	}
	write_pool(bytes, &entities.foundations)
	write_list(bytes, entities.frames.frames[:])
	append_u32(bytes, entities.frames.last_id)
	write_list(bytes, entity_frame_records(entities))
	write_belt_run_tables(bytes, entities, always)
}

// Ids rising from 1 up to the counter, and a pitch the transforms can
// divide by.
frames_are_consistent :: proc(table: Frame_Table) -> bool {
	previous := u32(0)
	for frame in table.frames {
		if u32(frame.id) <= previous || u32(frame.id) > table.last_id || frame.pitch_millimetres < MINIMUM_FOUNDATION_PITCH_MILLIMETRES || frame.pitch_millimetres > MAXIMUM_FOUNDATION_PITCH_MILLIMETRES {
			return false
		}
		previous = u32(frame.id)
	}
	return true
}

// See write_frame_tables. A save without them loads with every entity on
// frame 0: a save from before frames and a new world that never had a
// frame look alike (the header's version did not change, since the
// tables only append), so nothing is logged; no entity moves and no id is
// remapped.
read_frame_tables :: proc(reader: ^Byte_Reader, entities: ^Entities, machines: Machine_Registry) -> bool {
	clear(&entities.foundations.entries)
	clear(&entities.foundations.free)
	clear(&entities.frames.frames)
	entities.frames.last_id = 0
	if bytes_left(reader^) == 0 {
		return read_belt_run_tables(reader, entities, machines)
	}
	read_pool(reader, &entities.foundations, .Foundation, machines) or_return
	read_list(reader, &entities.frames.frames) or_return
	entities.frames.last_id = read_u32(reader) or_return
	frames_are_consistent(entities.frames) or_return
	records := make([dynamic]Entity_Frame_Record, context.temp_allocator)
	read_list(reader, &records) or_return
	for record in records {
		common := entity_common(entities, record.handle)
		if _, found := find_frame(&entities.frames, record.frame); common == nil || !found {
			return false
		}
		common.frame = record.frame
	}
	return read_belt_run_tables(reader, entities, machines)
}
