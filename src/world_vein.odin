package game

import "core:fmt"
import "core:slice"
import "generation_seed"

// What the simulation needs of a vein type: its id (for saves), its name,
// its outcrop blocks and its outputs as items with their percent weights,
// and per output the low grade twin or NO_ITEM.
Vein_Type_Content :: struct {
	id:             string,
	name_key:       string,
	outcrop_blocks: []Block_Id,
	output_count:   int,
	outputs:        [MAXIMUM_VEIN_OUTPUTS]Item_Id,
	low_grades:     [MAXIMUM_VEIN_OUTPUTS]Item_Id,
	percents:       [MAXIMUM_VEIN_OUTPUTS]i64,
}

// Indexed like Vein_Tables.types, so Vein.type indexes both.
// size_class_ids is indexed by Vein.size_class; each has a string
// vein_size_<id> (work item 0038, the assay names the class).
Vein_Content :: struct {
	types:          []Vein_Type_Content,
	spent_block:    Block_Id,
	size_class_ids: []string,
}

resolve_vein_type_content :: proc(vein_type: Vein_Type, items: Item_Registry) -> (content: Vein_Type_Content, problem: string) {
	definition := vein_type.definition
	content = Vein_Type_Content {
		id             = definition.id,
		name_key       = definition.name_key,
		outcrop_blocks = vein_type.outcrop_blocks,
		output_count   = len(definition.outputs),
	}
	for output, index in definition.outputs {
		item, found := find_item_id(items, output.ore)
		if !found {
			return {}, fmt.tprintf("vein type %q outputs unknown item %q", definition.id, output.ore)
		}
		content.outputs[index], content.percents[index] = item, output.percent
		content.low_grades[index] = NO_ITEM
		if output.low_grade != "" {
			if content.low_grades[index], found = find_item_id(items, output.low_grade); !found {
				return {}, fmt.tprintf("vein type %q names unknown low grade item %q", definition.id, output.low_grade)
			}
		}
	}
	return content, ""
}

resolve_vein_content :: proc(tables: Vein_Tables, items: Item_Registry, allocator := context.allocator) -> (content: Vein_Content, problem: string) {
	content.spent_block = tables.spent_block
	content.types = make([]Vein_Type_Content, len(tables.types), allocator)
	for vein_type, index in tables.types {
		if content.types[index], problem = resolve_vein_type_content(vein_type, items); problem != "" {
			delete(content.types, allocator)
			return {}, problem
		}
	}
	content.size_class_ids = make([]string, len(tables.size_classes), allocator)
	for size_class, index in tables.size_classes {
		content.size_class_ids[index] = size_class.id
	}
	return content, ""
}

// Adds the vein unless a chunk of another column registered it already.
register_vein :: proc(world: ^World, vein: Vein) {
	if vein.id in world.vein_indices {
		return
	}
	world.vein_indices[vein.id] = len(world.veins)
	append(&world.veins, vein)
}

// Called on the main thread for every inserted chunk. The first chunk of a
// column records the column's vein ids, later chunks of it change nothing.
register_column_veins :: proc(world: ^World, column: Chunk_Column, veins: []Vein) {
	if column in world.column_veins {
		return
	}
	ids := make([dynamic]Vein_Id, 0, len(veins))
	for vein in veins {
		register_vein(world, vein)
		append(&ids, vein.id)
	}
	world.column_veins[column] = ids
}

// The registered veins of both layers overlapping a chunk column, empty
// when no chunk of the column was loaded yet.
veins_of_column :: proc(world: ^World, column: Chunk_Column, allocator := context.allocator) -> []Vein {
	ids := world.column_veins[column] or_else nil
	veins := make([]Vein, len(ids), allocator)
	for id, index in ids {
		veins[index] = world.veins[world.vein_indices[id]]
	}
	return veins
}

vein_is_deep :: proc(vein: Vein) -> bool {
	return vein.id.layer == .Deep
}

// The registered deep vein whose disc holds the column (the first in
// placement order), for a bore drill standing over it.
deep_vein_at_column :: proc(world: ^World, x, z: i32) -> (id: Vein_Id, found: bool) {
	return deep_vein_in_columns(world.veins[:], world.vein_indices, world.column_veins, x, z)
}

deep_vein_in_columns :: proc(veins: []Vein, vein_indices: map[Vein_Id]int, column_veins: map[Chunk_Column][dynamic]Vein_Id, x, z: i32) -> (id: Vein_Id, found: bool) {
	column := chunk_column_of(world_to_chunk_coordinate({x, 0, z}))
	for vein_id in column_veins[column] or_else nil {
		vein := veins[vein_indices[vein_id]]
		if vein_is_deep(vein) && column_in_disc(vein.centre, vein.radius, x, z) {
			return vein.id, true
		}
	}
	return {}, false
}

// The registered surface vein whose disc holds the column (the first in
// placement order), whatever block is on the surface: the reservoir lies
// under the whole footprint, so a mined or built over outcrop still counts.
vein_at_column :: proc(world: ^World, x, z: i32) -> (id: Vein_Id, found: bool) {
	column := chunk_column_of(world_to_chunk_coordinate({x, 0, z}))
	for vein in veins_of_column(world, column, context.temp_allocator) {
		if !vein_is_deep(vein) && column_in_disc(vein.centre, vein.radius, x, z) {
			return vein.id, true
		}
	}
	return {}, false
}

// Nil for an id no chunk registered. Valid until the next vein registers.
registered_vein :: proc(world: ^World, id: Vein_Id) -> ^Vein {
	return vein_of_id(world.veins[:], world.vein_indices, id)
}

vein_of_id :: proc(veins: []Vein, vein_indices: map[Vein_Id]int, id: Vein_Id) -> ^Vein {
	index, found := vein_indices[id]
	return found ? &veins[index] : nil
}

// False as well for a vein type the content does not have.
vein_block_is_outcrop :: proc(veins: Vein_Content, vein: Vein, block: Block_Id) -> bool {
	return vein.type < len(veins.types) && block_is_outcrop_of(veins.types[vein.type], block)
}

block_is_outcrop_of :: proc(vein_type: Vein_Type_Content, block: Block_Id) -> bool {
	for outcrop in vein_type.outcrop_blocks {
		if outcrop == block {
			return true
		}
	}
	return false
}

// The registered vein whose outcrop the cell is part of: the cell's column
// lies in the vein's footprint disc and its block is one of the vein
// type's outcrop blocks. Only the geologist's hammer asks for the block;
// drills and the HUD go by the footprint (vein_at_column).
outcrop_vein_at :: proc(world: ^World, veins: Vein_Content, cell: World_Coordinate) -> (id: Vein_Id, found: bool) {
	block := world_get_block(world, cell)
	for vein in veins_of_column(world, chunk_column_of(world_to_chunk_coordinate(cell)), context.temp_allocator) {
		if column_in_disc(vein.centre, vein.radius, cell.x, cell.z) && vein_block_is_outcrop(veins, vein, block) {
			return vein.id, true
		}
	}
	return {}, false
}

// The registered vein whose outcrop cell this is, while the cell still
// holds one of the vein type's outcrop blocks. Unlike outcrop_vein_at it
// goes by the registered cells, so stone under a stone vein's outcrop
// does not count.
registered_outcrop_vein_at :: proc(world: ^World, veins: Vein_Content, cell: World_Coordinate) -> (id: Vein_Id, found: bool) {
	id, found = world.outcrop_cells[cell]
	if !found {
		return {}, false
	}
	vein := registered_vein(world, id)
	return id, vein != nil && vein_block_is_outcrop(veins, vein^, world_get_block(world, cell))
}

// Some registered outcrop cell of the vein still holds an outcrop block.
// A cell whose chunk is not loaded counts as holding one, since its
// block cannot be read.
vein_outcrop_remains :: proc(world: ^World, veins: Vein_Content, vein: Vein) -> bool {
	for position, id in world.outcrop_cells {
		if id != vein.id {
			continue
		}
		if world_to_chunk_coordinate(position) not_in world.chunks || vein_block_is_outcrop(veins, vein, world_get_block(world, position)) {
			return true
		}
	}
	return false
}

// After an outcrop block of the vein was mined (work item 0096): the
// last one is gone while the reservoir below still has units.
outcrop_spent_with_units_left :: proc(world: ^World, veins: Vein_Content, id: Vein_Id) -> bool {
	vein := registered_vein(world, id)
	if vein == nil || vein_is_deep(vein^) || vein_is_exhausted(vein^, world.settings.veins_infinite) {
		return false
	}
	return !vein_outcrop_remains(world, veins, vein^)
}

// Called on the main thread for every inserted chunk. Cells of a vein
// exhausted before the chunk loaded go straight to the spent queue, so the
// chunk comes out as spent rock too.
register_outcrop_cells :: proc(world: ^World, cells: []Outcrop_Cell) {
	for cell in cells {
		world.outcrop_cells[cell.position] = cell.vein
		if vein := registered_vein(world, cell.vein); vein != nil && vein.exhausted {
			append(&world.spent_outcrops, cell.position)
		}
	}
}

// The outcrop cells of loaded (and earlier loaded) chunks. Those whose
// chunk is gone drop out in apply_spent_outcrops and come back through
// register_outcrop_cells when the chunk loads again. Queued in coordinate
// order, since map order differs between a world and its loaded save.
queue_spent_outcrops :: proc(outcrop_cells: map[World_Coordinate]Vein_Id, spent_outcrops: ^[dynamic]World_Coordinate, id: Vein_Id) {
	first := len(spent_outcrops^)
	for position, vein in outcrop_cells {
		if vein == id {
			append(spent_outcrops, position)
		}
	}
	slice.sort_by(spent_outcrops^[first:], coordinate_before)
}

// Added veins (work item 0053): the developer command `vein` puts a new
// surface vein at a column. Generation knows nothing of it, so the world
// keeps it (in veins, saved, with added set) and applies it itself: the
// id is the next index of its region after the generated veins and the
// veins added there before, its centre lies on the generated surface, and
// its outcrop replaces the solid block at the generated surface height of
// every footprint column. Loaded chunks get the outcrop when the vein is
// added (through world_set_block), stored chunks are rewritten, and a
// chunk generated later gets it when it arrives (apply_added_veins_to_chunk).
// Unlike a generated vein it may reach past its region's border; the map
// survey and the orbital survey, which ask the generator, do not see it.

ADDED_VEIN_HASH_SALT :: 0x5eed_0053

// Surface veins already registered or generated whose disc, with the
// spacing, reaches the disc. A generated vein lies inside its region, so
// the regions around the disc's box hold every candidate.
added_vein_overlaps :: proc(world: ^World, generator: ^Generator, centre: World_Coordinate, radius: i32) -> bool {
	for vein in world.veins {
		if !vein_is_deep(vein) && discs_overlap(vein.centre, vein.radius, centre, radius) {
			return true
		}
	}
	reach := radius + VEIN_SPACING
	nearby := veins_near_box(generator, {centre.x - reach, centre.z - reach}, {centre.x + reach, centre.z + reach}, context.temp_allocator)
	return !disc_is_clear(nearby[:], centre, radius)
}

// After the region's generated surface veins and the veins added there
// before.
added_vein_next_index :: proc(world: ^World, generator: ^Generator, region: Region_Coordinate) -> i32 {
	index := i32(len(layer_veins(generator, region, .Surface, context.temp_allocator)))
	for vein in world.veins {
		if vein.added && vein.id.region == region && !vein_is_deep(vein) {
			index += 1
		}
	}
	return index
}

// A vein of the type and size class centred on the column's generated
// surface, sized and filled from the seed and the column like a natural
// vein of its region.
make_added_vein :: proc(generator: ^Generator, type_index, size_class_index: int, column: [2]i32) -> Vein {
	size_class := generator.veins.size_classes[size_class_index]
	region := block_to_region(column.x, column.y)
	richness := region_richness(generator.veins, region)
	hash := generation_seed.hash_combine(generation_seed.hash_column(generator.seeds[.Veins], column.x, column.y), ADDED_VEIN_HASH_SALT)
	units := vein_units(generator, size_class, richness, generation_seed.hash_combine(hash, 1))
	return Vein {
		type = type_index,
		size_class = size_class_index,
		centre = {column.x, sample_column(generator, column.x, column.y).height, column.y},
		radius = vein_radius(size_class, richness, hash),
		remaining = vein_amounts(generator.veins.types[type_index], units),
		added = true,
	}
}

// The outcrop cell of every footprint column: the generated surface
// height there. In the temp allocator.
added_vein_cells :: proc(generator: ^Generator, vein: Vein) -> []World_Coordinate {
	cells := make([dynamic]World_Coordinate, context.temp_allocator)
	for z in vein.centre.z - vein.radius ..= vein.centre.z + vein.radius {
		for x in vein.centre.x - vein.radius ..= vein.centre.x + vein.radius {
			if column_in_disc(vein.centre, vein.radius, x, z) {
				append(&cells, World_Coordinate{x, sample_column(generator, x, z).height, z})
			}
		}
	}
	return cells[:]
}

// Registers the vein, lists it in the loaded columns it reaches and
// stamps its outcrop into loaded and stored chunks. The caller checked
// that it overlaps no other vein. Returns its id.
add_vein :: proc(world: ^World, generator: ^Generator, vein: Vein) -> Vein_Id {
	added := vein
	region := block_to_region(vein.centre.x, vein.centre.z)
	added.id = Vein_Id{region = region, index = added_vein_next_index(world, generator, region), layer = .Surface}
	added.added = true
	register_vein(world, added)
	for column, &ids in world.column_veins {
		if vein_overlaps_column(added, column) {
			append(&ids, added.id)
		}
	}
	stored := make(map[Chunk_Coordinate][dynamic]World_Coordinate, context.temp_allocator)
	for cell in added_vein_cells(generator, added) {
		coordinate := world_to_chunk_coordinate(cell)
		switch {
		case coordinate in world.chunks:
			stamp_added_outcrop(world, generator, added, cell)
		case coordinate in world.saved_chunks:
			cells := stored[coordinate] or_else make([dynamic]World_Coordinate, context.temp_allocator)
			append(&cells, cell)
			stored[coordinate] = cells
		}
	}
	for coordinate, cells in stored {
		stamp_stored_chunk(world, generator, added, coordinate, cells[:])
	}
	return added.id
}

// A loaded cell: through world_set_block, so light and meshes follow.
stamp_added_outcrop :: proc(world: ^World, generator: ^Generator, vein: Vein, cell: World_Coordinate) {
	world.outcrop_cells[cell] = vein.id
	if block_is_solid(generator.registry, world_get_block(world, cell)) {
		world_set_block(world, cell, outcrop_block(generator, vein, cell.x, cell.z))
	}
}

// A chunk that is not loaded but was modified: its stored blocks get the
// outcrop, so it arrives with it.
stamp_stored_chunk :: proc(world: ^World, generator: ^Generator, vein: Vein, coordinate: Chunk_Coordinate, cells: []World_Coordinate) {
	chunk := new(Chunk, context.temp_allocator)
	chunk.coordinate = coordinate
	if !deserialize_chunk_blocks(world.saved_chunks[coordinate], &chunk.blocks) {
		return
	}
	for cell in cells {
		index := local_to_index(world_to_local_coordinate(cell))
		if block_is_solid(generator.registry, chunk.blocks[index]) {
			chunk.blocks[index] = outcrop_block(generator, vein, cell.x, cell.z)
		}
	}
	delete(world.saved_chunks[coordinate])
	world.saved_chunks[coordinate] = serialize_chunk(chunk)
}

// After a chunk arrived (world_streaming.odin): every added vein reaching
// its column joins the column's list and its outcrop cells in the chunk
// are registered. A freshly generated chunk also gets the outcrop blocks;
// a restored one holds them already (stamped when the vein was added, or
// before its blocks were stored).
apply_added_veins_to_chunk :: proc(world: ^World, generator: ^Generator, coordinate: Chunk_Coordinate, restored: bool) {
	column := chunk_column_of(coordinate)
	chunk := world.chunks[coordinate] or_else nil
	if chunk == nil {
		return
	}
	for vein in world.veins {
		if !vein.added || !vein_overlaps_column(vein, column) {
			continue
		}
		if ids, found := &world.column_veins[column]; found && !slice.contains(ids[:], vein.id) {
			append(ids, vein.id)
		}
		for cell in added_vein_cells(generator, vein) {
			if world_to_chunk_coordinate(cell) != coordinate {
				continue
			}
			world.outcrop_cells[cell] = vein.id
			index := local_to_index(world_to_local_coordinate(cell))
			if !restored && block_is_solid(generator.registry, chunk.blocks[index]) {
				chunk.blocks[index] = outcrop_block(generator, vein, cell.x, cell.z)
			}
		}
	}
}
