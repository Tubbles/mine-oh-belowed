package game

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
