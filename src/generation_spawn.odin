package game

import "base:runtime"

// Spawn search per doc/quests.md "Spawn requirements": trees, exposed
// stone, sand, water and one vein of each spawn vein type within about 150
// blocks. It queries the generator's column, feature and vein functions
// directly, so no chunk is generated.

SPAWN_REQUIREMENT_RADIUS :: 150
// Candidates lie on square rings around the origin, this far apart.
SPAWN_SEARCH_STEP :: 32
SPAWN_SEARCH_RING_COUNT :: 64
// Terrain around a candidate is sampled on a grid with this spacing.
SPAWN_SAMPLE_STEP :: 4

Spawn_Findings :: struct {
	trees:      bool,
	stone:      bool,
	sand:       bool,
	water:      bool,
	vein_types: u64,
}

within_spawn_radius :: proc(centre: [2]i32, x, z: i32) -> bool {
	dx := i64(x - centre.x)
	dz := i64(z - centre.y)
	return dx * dx + dz * dz <= SPAWN_REQUIREMENT_RADIUS * SPAWN_REQUIREMENT_RADIUS
}

spawn_vein_types_found :: proc(veins: []Vein, centre: [2]i32) -> u64 {
	found: u64 = 0
	for vein in veins {
		if within_spawn_radius(centre, vein.centre.x, vein.centre.z) {
			found |= u64(1) << u64(vein.type)
		}
	}
	return found
}

required_vein_mask :: proc(generator: ^Generator) -> u64 {
	mask: u64 = 0
	for type_index in generator.veins.spawn_types {
		mask |= u64(1) << u64(type_index)
	}
	return mask
}

record_column :: proc(generator: ^Generator, findings: ^Spawn_Findings, column: Column_Sample) {
	top_block := column_biome(generator, column).top_block
	findings.water ||= column.height < SEA_LEVEL
	findings.sand ||= top_block == generator.blocks.sand
	findings.stone ||= top_block == generator.blocks.stone
}

terrain_findings_complete :: proc(findings: Spawn_Findings) -> bool {
	return findings.water && findings.sand && findings.stone
}

scan_spawn_terrain :: proc(generator: ^Generator, centre: [2]i32, findings: ^Spawn_Findings) {
	for dz := i32(-SPAWN_REQUIREMENT_RADIUS); dz <= SPAWN_REQUIREMENT_RADIUS; dz += SPAWN_SAMPLE_STEP {
		for dx := i32(-SPAWN_REQUIREMENT_RADIUS); dx <= SPAWN_REQUIREMENT_RADIUS; dx += SPAWN_SAMPLE_STEP {
			x, z := centre.x + dx, centre.y + dz
			if within_spawn_radius(centre, x, z) {
				record_column(generator, findings, sample_column(generator, x, z))
			}
			if terrain_findings_complete(findings^) {
				return
			}
		}
	}
}

feature_near_spawn :: proc(generator: ^Generator, kind: Feature_Kind, centre: [2]i32, veins: []Vein) -> bool {
	cell_size := feature_cell_size(kind)
	first := [2]i32{floor_divide(centre.x - SPAWN_REQUIREMENT_RADIUS, cell_size), floor_divide(centre.y - SPAWN_REQUIREMENT_RADIUS, cell_size)}
	last := [2]i32{floor_divide(centre.x + SPAWN_REQUIREMENT_RADIUS, cell_size), floor_divide(centre.y + SPAWN_REQUIREMENT_RADIUS, cell_size)}
	for cell_z in first.y ..= last.y {
		for cell_x in first.x ..= last.x {
			root, found := feature_root(generator, kind, {cell_x, cell_z}, veins)
			if found && within_spawn_radius(centre, root.position.x, root.position.z) {
				return true
			}
		}
	}
	return false
}

// Cheapest checks first: dry ground, then veins, then the terrain scan,
// then trees and boulders.
evaluate_spawn :: proc(generator: ^Generator, centre: [2]i32) -> Spawn_Findings {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	findings: Spawn_Findings
	minimum := centre - SPAWN_REQUIREMENT_RADIUS
	veins := veins_near_box(generator, minimum, centre + SPAWN_REQUIREMENT_RADIUS, context.temp_allocator)
	findings.vein_types = spawn_vein_types_found(veins[:], centre)
	required := required_vein_mask(generator)
	if findings.vein_types & required != required {
		return findings
	}
	scan_spawn_terrain(generator, centre, &findings)
	if !findings.water || !findings.sand {
		return findings
	}
	findings.stone ||= feature_near_spawn(generator, .Boulder, centre, veins[:])
	findings.trees = feature_near_spawn(generator, .Tree, centre, veins[:])
	return findings
}

spawn_satisfied :: proc(generator: ^Generator, findings: Spawn_Findings) -> bool {
	required := required_vein_mask(generator)
	return terrain_findings_complete(findings) && findings.trees && findings.vein_types & required == required
}

// Candidates of ring r are the grid points on the square of half width r,
// in a fixed order.
spawn_ring_candidate :: proc(ring, index: i32) -> [2]i32 {
	side := 2 * ring
	edge, offset := index / side, index % side
	position: [2]i32
	switch edge {
	case 0:
		position = {-ring + offset, -ring}
	case 1:
		position = {ring, -ring + offset}
	case 2:
		position = {ring - offset, ring}
	case:
		position = {-ring, ring - offset}
	}
	return position * SPAWN_SEARCH_STEP
}

spawn_candidate_ok :: proc(generator: ^Generator, centre: [2]i32) -> (spawn: World_Coordinate, ok: bool) {
	column := sample_column(generator, centre.x, centre.y)
	if column.height <= SEA_LEVEL || !spawn_satisfied(generator, evaluate_spawn(generator, centre)) {
		return {}, false
	}
	return World_Coordinate{centre.x, column.height, centre.y}, true
}

// The surface block of the first candidate, from the origin outwards, that
// meets every requirement.
find_spawn :: proc(generator: ^Generator) -> (spawn: World_Coordinate, found: bool) {
	if spawn, found = spawn_candidate_ok(generator, {0, 0}); found {
		return
	}
	for ring in i32(1) ..< SPAWN_SEARCH_RING_COUNT {
		for index in i32(0) ..< 8 * ring {
			if spawn, found = spawn_candidate_ok(generator, spawn_ring_candidate(ring, index)); found {
				return
			}
		}
	}
	return {}, false
}
