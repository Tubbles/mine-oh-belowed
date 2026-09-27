package game

import "base:runtime"

// Spawn search per doc/quests.md "Spawn requirements": trees, exposed
// stone, sand and water within about 150 blocks, on flat ground (work item
// 0045), in a temperate climate (work item 0058). The iron, copper and coal outcrops are the starter veins placed
// around the landing pad (generation_starter_veins.odin), so the search
// needs no natural vein. It queries the generator's column and feature
// functions directly, so no chunk is generated.

SPAWN_REQUIREMENT_RADIUS :: 150
// Candidates lie on square rings around the origin, this far apart.
SPAWN_SEARCH_STEP :: 32
SPAWN_SEARCH_RING_COUNT :: 96
// Terrain around a candidate is sampled on a grid with this spacing.
SPAWN_SAMPLE_STEP :: 4
// Within LANDING_SITE_FLAT_RADIUS blocks of the pad the sampled surface
// heights differ by at most LANDING_SITE_FLAT_HEIGHT_RANGE and no column is
// water. Within LANDING_SITE_SURROUNDINGS_RADIUS they differ by at most
// LANDING_SITE_SURROUNDINGS_HEIGHT_RANGE, which keeps river gorges and
// cliffs away from the pad. The detail noise alone (DETAIL_AMPLITUDE)
// varies the surface by about 5 blocks, so a flat range of 3 left no site
// on any seed tried (work item 0045 notes).
LANDING_SITE_FLAT_RADIUS :: 24
LANDING_SITE_FLAT_HEIGHT_RANGE :: 5
LANDING_SITE_SURROUNDINGS_RADIUS :: 64
LANDING_SITE_SURROUNDINGS_HEIGHT_RANGE :: 12
// Starter vein centres lie this many blocks from the pad centre: past the
// flat ring, and close enough to be seen from the pad.
STARTER_VEIN_MINIMUM_DISTANCE :: 24
STARTER_VEIN_MAXIMUM_DISTANCE :: 40
// The pad's column lies in this temperature range (terrain_temperature),
// so chapter 1 starts on grass rather than snow or red rock. The origin
// is temperate by construction (ORIGIN_TEMPERATURE).
SPAWN_MINIMUM_TEMPERATURE :: -0.2
SPAWN_MAXIMUM_TEMPERATURE :: 0.5

Spawn_Findings :: struct {
	temperate: bool,
	flat:      bool,
	trees:     bool,
	stone:     bool,
	sand:      bool,
	water:     bool,
}

within_spawn_radius :: proc(centre: [2]i32, x, z: i32) -> bool {
	dx := i64(x - centre.x)
	dz := i64(z - centre.y)
	return dx * dx + dz * dz <= SPAWN_REQUIREMENT_RADIUS * SPAWN_REQUIREMENT_RADIUS
}

Height_Range :: struct {
	lowest:  i32,
	highest: i32,
	water:   bool,
}

// Surface heights on the sample grid within radius of the centre.
sample_height_range :: proc(generator: ^Generator, centre: [2]i32, radius: i32) -> Height_Range {
	heights := Height_Range{lowest = max(i32), highest = min(i32)}
	for dz := -radius; dz <= radius; dz += SPAWN_SAMPLE_STEP {
		for dx := -radius; dx <= radius; dx += SPAWN_SAMPLE_STEP {
			if dx * dx + dz * dz > radius * radius {
				continue
			}
			height := terrain_height(generator.seeds, centre.x + dx, centre.y + dz)
			heights.lowest = min(heights.lowest, height)
			heights.highest = max(heights.highest, height)
			heights.water ||= height < SEA_LEVEL
		}
	}
	return heights
}

landing_site_is_flat :: proc(generator: ^Generator, centre: [2]i32) -> bool {
	near := sample_height_range(generator, centre, LANDING_SITE_FLAT_RADIUS)
	if near.water || near.highest - near.lowest > LANDING_SITE_FLAT_HEIGHT_RANGE {
		return false
	}
	surroundings := sample_height_range(generator, centre, LANDING_SITE_SURROUNDINGS_RADIUS)
	return surroundings.highest - surroundings.lowest <= LANDING_SITE_SURROUNDINGS_HEIGHT_RANGE
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

spawn_is_temperate :: proc(generator: ^Generator, centre: [2]i32) -> bool {
	height := terrain_height(generator.seeds, centre.x, centre.y)
	temperature := terrain_temperature(generator.seeds, centre.x, centre.y, height)
	return temperature >= SPAWN_MINIMUM_TEMPERATURE && temperature <= SPAWN_MAXIMUM_TEMPERATURE
}

// Cheapest checks first: the climate of the pad's column, flat ground,
// then the terrain scan, then trees and boulders.
evaluate_spawn :: proc(generator: ^Generator, centre: [2]i32) -> Spawn_Findings {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	findings: Spawn_Findings
	findings.temperate = spawn_is_temperate(generator, centre)
	if !findings.temperate {
		return findings
	}
	findings.flat = landing_site_is_flat(generator, centre)
	if !findings.flat {
		return findings
	}
	scan_spawn_terrain(generator, centre, &findings)
	if !findings.water || !findings.sand {
		return findings
	}
	minimum := centre - SPAWN_REQUIREMENT_RADIUS
	veins := veins_near_box(generator, minimum, centre + SPAWN_REQUIREMENT_RADIUS, context.temp_allocator)
	findings.stone ||= feature_near_spawn(generator, .Boulder, centre, veins[:])
	findings.trees = feature_near_spawn(generator, .Tree, centre, veins[:])
	return findings
}

spawn_satisfied :: proc(findings: Spawn_Findings) -> bool {
	return findings.temperate && findings.flat && terrain_findings_complete(findings) && findings.trees
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
	if column.height <= SEA_LEVEL || !spawn_satisfied(evaluate_spawn(generator, centre)) {
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
