package game

// The landing pad at the spawn: a 5 by 5 platform of landing_pad blocks
// (not minable) with the drop capsule standing on one corner.
//
// World generation stamps the pad, rather than the simulation placing it
// on first load. The spawn is a function of the seed, and generation is a
// pure function of the seed and the chunk coordinate, so every chunk the
// pad touches regenerates it identically, on any thread and after any
// reload, with no "pad placed" flag to keep or save. The capsule is an
// entity, and entities are simulation state, so make_simulation adds it.

LANDING_PAD_HALF_WIDTH :: 2
// Air cleared above the pad, so trunks and boulders do not stand on it.
LANDING_PAD_CLEARANCE :: 10
// From the pad centre: the corner the player faces at the spawn (yaw 45).
CAPSULE_OFFSET :: World_Coordinate{LANDING_PAD_HALF_WIDTH, 1, LANDING_PAD_HALF_WIDTH}

// centre is the pad block under the spawn.
Landing_Pad_Site :: struct {
	present: bool,
	centre:  World_Coordinate,
}

landing_pad_box :: proc(site: Landing_Pad_Site) -> Block_Box {
	half := World_Coordinate{LANDING_PAD_HALF_WIDTH, 0, LANDING_PAD_HALF_WIDTH}
	return Block_Box{minimum = site.centre - half, maximum = site.centre + half + {0, LANDING_PAD_CLEARANCE, 0}}
}

// The pad layer, and air above it up to the clearance.
apply_landing_pad :: proc(site: Landing_Pad_Site, pad_block: Block_Id, chunk: ^Chunk) {
	if !site.present {
		return
	}
	box := clip_box_to_chunk(landing_pad_box(site), chunk.coordinate)
	origin := chunk_origin(chunk.coordinate)
	for y in box.minimum.y ..= box.maximum.y {
		for z in box.minimum.z ..= box.maximum.z {
			for x in box.minimum.x ..= box.maximum.x {
				index := local_to_index(Local_Coordinate(World_Coordinate{x, y, z} - origin))
				chunk.blocks[index] = y == site.centre.y ? pad_block : AIR_BLOCK
			}
		}
	}
}

// Where the terrain lies below the pad, the pad is what closes the column
// to the sky.
close_landing_pad_columns :: proc(site: Landing_Pad_Site, coordinate: Chunk_Coordinate, open: ^Open_Columns) {
	if !site.present {
		return
	}
	box := clip_box_to_chunk(landing_pad_box(site), coordinate)
	origin := chunk_origin(coordinate)
	if site.centre.y < origin.y || box.minimum.x > box.maximum.x || box.minimum.z > box.maximum.z {
		return
	}
	for z in box.minimum.z ..= box.maximum.z {
		for x in box.minimum.x ..= box.maximum.x {
			open[column_index(x - origin.x, z - origin.z)] &&= site.centre.y < origin.y + CHUNK_SIZE
		}
	}
}

// The capsule on the pad, or NO_ENTITY without a site or a capsule machine.
place_capsule :: proc(entities: ^Entities, machines: Machine_Registry, site: Landing_Pad_Site) -> Entity_Handle {
	machine := find_machine_of_kind(machines, .Capsule)
	if !site.present || machine == NO_MACHINE {
		return NO_ENTITY
	}
	return add_entity(entities, machines, machine, site.centre + CAPSULE_OFFSET, 0)
}
