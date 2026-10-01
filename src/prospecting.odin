package game

import "core:fmt"
import "core:math"

// The prospecting ladder of DESIGN.md (work item 0038). Each tool reveals
// one attribute and leaves a record in the game records, drawn on the map
// (ui_map.odin) and saved:
// - The geologist's hammer, used on an outcrop block, assays its vein:
//   type (hence the ore mix), size class and footprint disc.
// - The magnetometer, while it is the selected hotbar item, reads the
//   nearest registered vein (surface or deep) that yields the item it
//   detects within its range, measured across (a buried vein counts at
//   any depth); Use records the reading as a point with a direction.
// - The core sample drill, after its powered sampling time, reports the
//   strata below its column (the most common block per depth band, as far
//   down as chunks are loaded) and the deep vein under its column.
// - A thumper charge fired at the ground images every deep vein whose
//   disc reaches within its range: centre and radius, no composition.
//   The third shot covering a vein resolves it.

CORE_SAMPLE_BAND_DEPTH :: 16
CORE_SAMPLE_BAND_COUNT :: 8
SEISMIC_SHOTS_TO_RESOLVE :: 3
MAGNETOMETER_FULL :: 1000

// A known vein, drawn on the map. from_spent_outcrop marks a record made
// only because its outcrop was mined away (work item 0096): the vein is
// known but not assayed. outcrop_spent marks that Mission Control said so,
// once per vein. Older saves read both as false.
Assayed_Vein :: struct {
	vein:               Vein_Id,
	type:               int,
	size_class:         int,
	centre:             World_Coordinate,
	radius:             i32,
	from_spent_outcrop: bool,
	outcrop_spent:      bool,
}

// Taken at origin (block x and z); offset points from there to the vein's
// centre. strength is in per mille, 0 without a vein in range.
Magnetometer_Reading :: struct {
	origin:   [2]i32,
	offset:   [2]i32,
	strength: u16,
	found:    bool,
}

// position is the drill's origin. bands[0] starts right below it, each
// band CORE_SAMPLE_BAND_DEPTH blocks; band_count stops at the first band
// reaching an unloaded chunk. vein_depth is from the drill's origin down
// to the deep vein's centre.
Core_Sample :: struct {
	position:   World_Coordinate,
	bands:      [CORE_SAMPLE_BAND_COUNT]Block_Id,
	band_count: i32,
	vein_found: bool,
	vein:       Vein_Id,
	vein_type:  int,
	vein_depth: i32,
}

Seismic_Shot :: struct {
	position: World_Coordinate,
}

// One per deep vein any shot imaged, with the shots that covered it.
Seismic_Outline :: struct {
	vein:       Vein_Id,
	centre:     World_Coordinate,
	radius:     i32,
	shot_count: u32,
	resolved:   bool,
}

// sample indexes Game_Records.core_samples once reported, -1 before.
Core_Sample_Drill :: struct {
	using common: Entity_Common,
	power:        Power_State,
	work_ticks:   u32,
	sample:       i32,
}

make_core_sample_drill :: proc(common: Entity_Common) -> Core_Sample_Drill {
	return Core_Sample_Drill{common = common, sample = -1}
}

// One by one by two, electric, with a sampling time and no slots.
validate_core_sample_drill_definition :: proc(definition: Machine_Definition) -> string {
	footprint := definition.footprint
	if footprint.width != 1 || footprint.depth != 1 || footprint.height != 2 {
		return fmt.tprintf("core sample drill %q must be 1 by 1 by 2", definition.id)
	}
	if definition.electric_power_kilowatts <= 0 || definition.sampling_seconds <= 0 {
		return fmt.tprintf("core sample drill %q needs a positive electric_power_kilowatts and sampling_seconds", definition.id)
	}
	if definition.slots != 0 || definition.fuel_slots != 0 || definition.input_slots != 0 || definition.output_slots != 0 {
		return fmt.tprintf("core sample drill %q may not list slots", definition.id)
	}
	return ""
}

// The geologist's hammer.

// The index of the vein's record in Game_Records.assayed_veins, or -1.
known_vein_index :: proc(assayed_veins: []Assayed_Vein, id: Vein_Id) -> int {
	for assayed, index in assayed_veins {
		if assayed.vein == id {
			return index
		}
	}
	return -1
}

// Known from a spent outcrop alone does not count.
vein_is_assayed :: proc(assayed_veins: []Assayed_Vein, id: Vein_Id) -> bool {
	index := known_vein_index(assayed_veins, id)
	return index >= 0 && !assayed_veins[index].from_spent_outcrop
}

assayed_vein_record :: proc(vein: Vein) -> Assayed_Vein {
	return Assayed_Vein{vein = vein.id, type = vein.type, size_class = vein.size_class, centre = vein.centre, radius = vein.radius}
}

// Assays the vein whose outcrop the cell is; false for any other block
// and for a vein assayed before. A record from a spent outcrop becomes
// an assayed one.
assay_vein :: proc(world: ^World, records: ^Game_Records, veins: Vein_Content, cell: World_Coordinate) -> bool {
	id, found := outcrop_vein_at(world, veins, cell)
	if !found || vein_is_assayed(records.assayed_veins[:], id) {
		return false
	}
	if index := known_vein_index(records.assayed_veins[:], id); index >= 0 {
		records.assayed_veins[index].from_spent_outcrop = false
	} else {
		append(&records.assayed_veins, assayed_vein_record(registered_vein(world, id)^))
	}
	records.statistics.veins_assayed += 1
	return true
}

// A spent outcrop (work item 0096): the vein's outcrop was mined away
// with units left, so the vein counts as known and the map keeps its
// footprint. Returns true, and counts it for Mission Control, the first
// time for the vein.
record_spent_outcrop :: proc(world: ^World, records: ^Game_Records, id: Vein_Id) -> bool {
	index := known_vein_index(records.assayed_veins[:], id)
	if index >= 0 && records.assayed_veins[index].outcrop_spent {
		return false
	}
	if index < 0 {
		record := assayed_vein_record(registered_vein(world, id)^)
		record.from_spent_outcrop = true
		append(&records.assayed_veins, record)
		index = len(records.assayed_veins) - 1
	}
	records.assayed_veins[index].outcrop_spent = true
	records.statistics.outcrops_spent += 1
	return true
}

// The magnetometer.

vein_yields_item :: proc(veins: Vein_Content, vein: Vein, item: Item_Id) -> bool {
	if vein.type >= len(veins.types) {
		return false
	}
	vein_type := veins.types[vein.type]
	for output in vein_type.outputs[:vein_type.output_count] {
		if output == item {
			return true
		}
	}
	return false
}

// Across only, from a point to the nearest column of the disc, 0 inside.
distance_to_disc :: proc(position: [2]f64, vein: Vein) -> f64 {
	offset := [2]f64{f64(vein.centre.x) + 0.5 - position.x, f64(vein.centre.z) + 0.5 - position.y}
	return max(math.sqrt(offset.x * offset.x + offset.y * offset.y) - f64(vein.radius), 0)
}

// Full at the disc, falling linearly to 0 at the range.
magnetometer_strength :: proc(distance: f64, range: i32) -> u16 {
	if range <= 0 || distance >= f64(range) {
		return 0
	}
	return u16((f64(range) - distance) / f64(range) * MAGNETOMETER_FULL)
}

// The nearest vein yielding the item within the range, the first one in
// registration order on a tie.
magnetometer_reading :: proc(veins: []Vein, content: Vein_Content, detects: Item_Id, range: i32, position: [3]f32) -> Magnetometer_Reading {
	across := [2]f64{f64(position.x), f64(position.z)}
	reading := Magnetometer_Reading {
		origin = {i32(math.floor(position.x)), i32(math.floor(position.z))},
	}
	nearest := f64(range)
	for vein in veins {
		if !vein_yields_item(content, vein, detects) {
			continue
		}
		distance := distance_to_disc(across, vein)
		if distance <= nearest && (!reading.found || distance < nearest) {
			nearest = distance
			reading.found = true
			reading.offset = {vein.centre.x - reading.origin.x, vein.centre.z - reading.origin.y}
			reading.strength = magnetometer_strength(distance, range)
		}
	}
	return reading
}

// Every tick: the reading of the selected magnetometer, or none.
update_magnetometer :: proc(world: ^World, content: Simulation_Content, player: ^Player) {
	stack := selected_hotbar_stack(player^)
	if stack_is_empty(stack) || !item_has_use(content.items, stack.item, .Magnetometer) {
		player.magnetometer = {}
		return
	}
	item := content.items.items[stack.item]
	player.magnetometer = magnetometer_reading(world.veins[:], content.veins, item.detects, item.use_range, player.position)
}

// Seismic survey.

// The disc reaches within range of the shot, measured across.
disc_within_reach :: proc(position: World_Coordinate, range: i32, vein: Vein) -> bool {
	dx, dz := i64(vein.centre.x - position.x), i64(vein.centre.z - position.z)
	reach := i64(range) + i64(vein.radius)
	return dx * dx + dz * dz <= reach * reach
}

record_seismic_outline :: proc(outlines: ^[dynamic]Seismic_Outline, statistics: ^Statistics, vein: Vein) {
	outline: ^Seismic_Outline
	for &candidate in outlines {
		if candidate.vein == vein.id {
			outline = &candidate
		}
	}
	if outline == nil {
		append(outlines, Seismic_Outline{vein = vein.id, centre = vein.centre, radius = vein.radius})
		outline = &outlines[len(outlines) - 1]
	}
	outline.shot_count += 1
	if !outline.resolved && outline.shot_count >= SEISMIC_SHOTS_TO_RESOLVE {
		outline.resolved = true
		statistics.veins_resolved += 1
	}
}

fire_seismic_shot :: proc(world: ^World, records: ^Game_Records, position: World_Coordinate, range: i32) {
	append(&records.seismic_shots, Seismic_Shot{position = position})
	records.statistics.seismic_shots += 1
	for vein in world.veins {
		if vein_is_deep(vein) && disc_within_reach(position, range, vein) {
			record_seismic_outline(&records.seismic_outlines, &records.statistics, vein)
		}
	}
}

// Using items.

// Schematics are used up when read, a thumper charge when it is fired at
// a targeted block; the tools stay.
use_consumes_item :: proc(use: Item_Use, target_hit: bool) -> bool {
	switch use {
	case .Read:
		return true
	case .Seismic_Shot:
		return target_hit
	case .Assay, .Magnetometer:
		return false
	}
	return false
}

// What Use_Item did with the used item, acting on the target of the
// previous tick like resolve_use_item. Returns the event for the toast,
// if any.
apply_item_use :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, used: Item_Id) -> (event: Player_Event, happened: bool) {
	world, records := &state.world, &state.records
	player := &state.players[index]
	target := player.target
	item := content.items.items[used]
	switch item.use {
	case .Read:
		read_schematic(&state.unlocks, &state.quests, &records.statistics, content.recipes, used, state.tick)
	case .Assay:
		if target.hit && target.entity == NO_ENTITY && assay_vein(world, records, content.veins, target.block) {
			return .Vein_Assayed, true
		}
	case .Magnetometer:
		append(&records.magnetometer_readings, player.magnetometer)
		return .Magnetometer_Recorded, true
	case .Seismic_Shot:
		if target.hit {
			fire_seismic_shot(world, records, target.block, item.use_range)
			return .Seismic_Shot_Fired, true
		}
	}
	return {}, false
}

// Core sample drills.

core_sample_ticks :: proc(machine: Machine, tick_rate: int) -> u32 {
	return machine.sampling_seconds * u32(tick_rate)
}

core_sample_drill_wants_power :: proc(drill: Core_Sample_Drill) -> bool {
	return drill.sample < 0
}

// The first block with the highest count.
most_counted_block :: proc(counts: []u32) -> Block_Id {
	best := 0
	for count, index in counts {
		if count > counts[best] {
			best = index
		}
	}
	return Block_Id(best)
}

// The most common block of a band from top down, or not known when the
// band reaches into an unloaded chunk.
dominant_band_block :: proc(world: ^World, block_count: int, x, z, top: i32) -> (block: Block_Id, known: bool) {
	counts := make([]u32, max(block_count, 1), context.temp_allocator)
	for depth in 0 ..< i32(CORE_SAMPLE_BAND_DEPTH) {
		cell := World_Coordinate{x, top - depth, z}
		if world_to_chunk_coordinate(cell) not_in world.chunks {
			return AIR_BLOCK, false
		}
		sampled := world_get_block(world, cell)
		if int(sampled) < len(counts) {
			counts[sampled] += 1
		}
	}
	return most_counted_block(counts), true
}

take_core_sample :: proc(world: ^World, block_count: int, position: World_Coordinate) -> Core_Sample {
	sample := Core_Sample{position = position}
	for band in 0 ..< CORE_SAMPLE_BAND_COUNT {
		top := position.y - 1 - i32(band) * CORE_SAMPLE_BAND_DEPTH
		block, known := dominant_band_block(world, block_count, position.x, position.z, top)
		if !known {
			break
		}
		sample.bands[band] = block
		sample.band_count += 1
	}
	if id, found := deep_vein_at_column(world, position.x, position.z); found {
		vein := registered_vein(world, id)
		sample.vein_found, sample.vein, sample.vein_type = true, id, vein.type
		sample.vein_depth = position.y - vein.centre.y
	}
	return sample
}

// Works one tick per full tick of power until the sampling time is done,
// then reports once.
tick_core_sample_drills :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, tick_rate: int) {
	for &drill in world.entities.core_sample_drills.entries {
		if !drill.alive || !core_sample_drill_wants_power(drill) || !take_power_step(&drill.power) {
			continue
		}
		drill.work_ticks += 1
		if drill.work_ticks >= core_sample_ticks(content.machines.machines[drill.machine], tick_rate) {
			drill.sample = i32(len(records.core_samples))
			append(&records.core_samples, take_core_sample(world, len(content.blocks.definitions), drill.origin))
			records.statistics.core_samples_taken += 1
		}
	}
}

// The drill's report, nil before it is taken.
core_sample_of :: proc(core_samples: []Core_Sample, drill: Core_Sample_Drill) -> ^Core_Sample {
	if drill.sample < 0 || int(drill.sample) >= len(core_samples) {
		return nil
	}
	return &core_samples[drill.sample]
}
