package game

import "core:fmt"
import "core:slice"

// Chosen at world creation (DESIGN.md, World settings). The seed also
// seeds the drills' reservoir draws (drill.odin).
World_Settings :: struct {
	seed:                  u64,
	veins_infinite:        bool,
	// Written to world.sjson here; the generator and the technology
	// registry of the session apply them (session.odin).
	vein_richness_percent: int,
	research_cost_percent: int,
	// Stored for the byproduct rules to come, no effect yet.
	byproducts_lenient:    bool,
}

// What the simulation needs of a vein type: its name, its outcrop blocks
// and its outputs as items with their percent weights.
Vein_Type_Content :: struct {
	name_key:       string,
	outcrop_blocks: []Block_Id,
	output_count:   int,
	outputs:        [MAXIMUM_VEIN_OUTPUTS]Item_Id,
	percents:       [MAXIMUM_VEIN_OUTPUTS]i64,
}

// Indexed like Vein_Tables.types, so Vein.type indexes both.
Vein_Content :: struct {
	types:       []Vein_Type_Content,
	spent_block: Block_Id,
}

resolve_vein_type_content :: proc(vein_type: Vein_Type, items: Item_Registry) -> (content: Vein_Type_Content, problem: string) {
	definition := vein_type.definition
	content = Vein_Type_Content {
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

// The registered veins overlapping a chunk column, empty when no chunk of
// the column was loaded yet.
veins_of_column :: proc(world: ^World, column: Chunk_Column, allocator := context.allocator) -> []Vein {
	ids := world.column_veins[column] or_else nil
	veins := make([]Vein, len(ids), allocator)
	for id, index in ids {
		veins[index] = world.veins[world.vein_indices[id]]
	}
	return veins
}

// Nil for an id no chunk registered. Valid until the next vein registers.
registered_vein :: proc(world: ^World, id: Vein_Id) -> ^Vein {
	index, found := world.vein_indices[id]
	return found ? &world.veins[index] : nil
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
// type's outcrop blocks.
outcrop_vein_at :: proc(world: ^World, veins: Vein_Content, cell: World_Coordinate) -> (id: Vein_Id, found: bool) {
	block := world_get_block(world, cell)
	for vein in veins_of_column(world, chunk_column_of(world_to_chunk_coordinate(cell)), context.temp_allocator) {
		if column_in_disc(vein.centre, vein.radius, cell.x, cell.z) && vein_block_is_outcrop(veins, vein, block) {
			return vein.id, true
		}
	}
	return {}, false
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
queue_spent_outcrops :: proc(world: ^World, id: Vein_Id) {
	first := len(world.spent_outcrops)
	for position, vein in world.outcrop_cells {
		if vein == id {
			append(&world.spent_outcrops, position)
		}
	}
	slice.sort_by(world.spent_outcrops[first:], coordinate_before)
}

// Through world_set_block, so light and remeshing follow. A cell the
// player mined or built over keeps its block.
apply_spent_outcrops :: proc(world: ^World, veins: Vein_Content) {
	for position in world.spent_outcrops {
		vein := registered_vein(world, world.outcrop_cells[position])
		if vein != nil && vein_block_is_outcrop(veins, vein^, world_get_block(world, position)) {
			world_set_block(world, position, veins.spent_block)
		}
	}
	clear(&world.spent_outcrops)
}
