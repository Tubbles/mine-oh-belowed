package game

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:testing"
import "generation_seed"

// Work item 0327: the caves and the walls' undercuts.

// The caves as the design tuned them, on the landmarks' design planet
// (design_landmark_test_planet), so a later data retune leaves the tests.
DESIGN_TEST_CAVES :: Planet_Caves {
	region_caves_percent        = {0, 0, 0, 30, 70, 100, 100, 100, 100},
	shell_metres                = 32,
	dry_metres                  = 2,
	presence_wavelength_metres  = 420,
	presence_threshold_percent  = -20,
	level_metres                = 18,
	level_wavelength_metres     = 520,
	level_swing_metres          = 9,
	tunnel_wavelength_metres    = 96,
	tunnel_width_millimetres    = 2400,
	tunnel_height_millimetres   = 1600,
	chamber_wavelength_metres   = 56,
	chamber_threshold_percent   = 45,
	roof_metres                 = 8,
	undercut_wavelength_metres  = 40,
	undercut_threshold_percent  = -20,
	undercut_reach_millimetres  = 3000,
	undercut_height_millimetres = 2000,
}

design_caves_test_planet :: proc(radius_metres: int) -> Planet {
	planet := design_landmark_test_planet(radius_metres)
	planet.caves = DESIGN_TEST_CAVES
	return planet
}

// The column's point on the sphere at a ring's offset from the camera's
// radial, in spacings along the camera's tangents.
test_cave_ring_point :: proc(generation: Planet_Generation, up, forward, right: [3]i64, ahead, aside: i64) -> [3]i64 {
	point := fixed_scale(up, generation.radius) + fixed_scale(forward, ahead * generation.spacing) + fixed_scale(right, aside * generation.spacing)
	return project_onto_sphere(World_Position(point), vector_length(point), generation.radius)
}

// Whether the sample is cave air: air its column without the cave makes
// ground (no notch's, no site's); with its shade.
test_cave_air_sample :: proc(generation: Planet_Generation, sample: Sample_Coordinate) -> (air, shaded: bool) {
	position := sample_to_world_position(sample, generation.spacing_millimetres)
	value, is_shaded, _ := planet_sample_reading(generation, position)
	if value.density > 0 {
		return false, false
	}
	distance := vector_length(cast([3]i64)position)
	on_sphere := project_onto_sphere(position, distance, generation.radius)
	column := surface_column(generation, on_sphere)
	if depth_to_density(sample_depth(generation, column, {}, position, distance, on_sphere), generation.spacing_millimetres) <= 0 {
		return false, false
	}
	return true, is_shaded
}

// The first cave air sample whose march is open, scanning square rings of
// columns outward from the camera at the spacing to 112 m (the 7 by 7 by
// 7 chunks' footprint), each from the relief less the shell to the
// relief, and the roofed one an air path of the fewest steps within 8 m
// of it reaches first (so the fill lights it from the open one); found
// false when the scan holds none.
test_cave_mouth :: proc(generation: Planet_Generation, camera: World_Position) -> (open, roofed: Sample_Coordinate, found: bool) {
	up, _ := normalize_fixed(cast([3]i64)camera)
	forward := tangent_of(up, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, up)
	rings := metres_to_position_units(112) / generation.spacing
	shell := metres_to_position_units(i64(generation.caves.shell_metres))
	for ring in i64(0) ..= rings {
		for ahead in -ring ..= ring {
			for aside in -ring ..= ring {
				if max(abs(ahead), abs(aside)) != ring {
					continue
				}
				point := test_cave_ring_point(generation, up, forward, right, ahead, aside)
				column := surface_column(generation, point)
				cave := cave_column(generation, column, point)
				if cave.strength == 0 {
					continue
				}
				direction, _ := normalize_fixed(point)
				for height := column.relief - shell; height <= column.relief; height += generation.spacing {
					distance := generation.radius + height
					if depth_to_density(sample_depth(generation, column, cave, World_Position(fixed_scale(direction, distance)), distance, point), generation.spacing_millimetres) > 0 {
						continue
					}
					sample := nearest_field_sample(World_Position(fixed_scale(direction, distance)), generation.spacing_millimetres)
					if air, shaded := test_cave_air_sample(generation, sample); air && !shaded {
						if roofed, found = test_nearest_roofed_cave_air(generation, sample); found {
							return sample, roofed, true
						}
					}
				}
			}
		}
	}
	return
}

// The roofed cave air sample an air path from the start reaches in the
// fewest steps, within 8 m of it on every axis.
test_nearest_roofed_cave_air :: proc(generation: Planet_Generation, start: Sample_Coordinate) -> (roofed: Sample_Coordinate, found: bool) {
	reach := i32(metres_to_position_units(8) / generation.spacing)
	seen := make(map[Sample_Coordinate]struct{}, context.temp_allocator)
	queue := make([dynamic]Sample_Coordinate, context.temp_allocator)
	append(&queue, start)
	seen[start] = {}
	for head := 0; head < len(queue); head += 1 {
		sample := queue[head]
		if air, shaded := test_cave_air_sample(generation, sample); air && shaded {
			return sample, true
		}
		for offset in FIELD_LIGHT_NEIGHBOUR_OFFSETS {
			next := sample + Sample_Coordinate(offset)
			if _, visited := seen[next]; visited || max(abs(next.x - start.x), abs(next.y - start.y), abs(next.z - start.z)) > reach {
				continue
			}
			seen[next] = {}
			if planet_sample(generation, sample_to_world_position(next, generation.spacing_millimetres)).density <= 0 {
				append(&queue, next)
			}
		}
	}
	return
}

// The walls a notch cuts (Landmark_Kind holds only the sites).
Notch_Kind :: enum u8 {
	Gorge,
	Mesa,
}

// Whether the point lies in a patch of the kind: a gorge's where the
// first warp noise (Landform_Reading.mask) lies under minus the gorges'
// mask, a mesa's where it lies over the mesas'. One noise.
test_in_notch_patch :: proc(generation: Planet_Generation, point: [3]i64, kind: Notch_Kind) -> bool {
	mask := gradient_noise(generation_seed.hash_combine(generation.landform_seed, 0), point, metres_to_position_units(i64(generation.landforms.warp_wavelength_metres)))
	if kind == .Gorge {
		return -mask > i64(generation.landmarks.gorge_mask_percent) * NOISE_ONE / 100
	}
	return mask > i64(generation.landmarks.mesa_mask_percent) * NOISE_ONE / 100
}

// The notch's half height at its offset from the face: the ellipse's.
test_notch_extent :: proc(notch: Wall_Undercut) -> i64 {
	return notch.half_height * i64(integer_square_root(u64(notch.reach * notch.reach - notch.offset * notch.offset))) / notch.reach
}

// The nearest column to the home on 2 m square rings out to 1500 m whose
// notch is of the kind and overhangs: the column lies in the rock within
// the notch's reach from the wall's face, so the notch is air at its
// centre there, and its relief stands 1.5 m or more over the notch's top
// in it (at a quarter of the reach the walls, 50 to 60 degrees steep,
// leave the notch open at the top: the overhang stands over its far
// part).
test_nearest_notch :: proc(generation: Planet_Generation, kind: Notch_Kind) -> (column: [3]i64, notch: Wall_Undercut, found: bool) {
	up, _ := normalize_fixed(generation.landform_home)
	forward := tangent_of(up, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, up)
	step := metres_to_position_units(2)
	for ring in i64(0) ..= 750 {
		for ahead in -ring ..= ring {
			for aside in -ring ..= ring {
				if max(abs(ahead), abs(aside)) != ring {
					continue
				}
				point := generation.landform_home + fixed_scale(forward, ahead * step) + fixed_scale(right, aside * step)
				point = project_onto_sphere(World_Position(point), vector_length(point), generation.radius)
				if !test_in_notch_patch(generation, point, kind) {
					continue
				}
				surface := surface_column(generation, point)
				undercut := surface.undercut
				if undercut.reach == 0 || undercut.offset <= 0 || undercut.offset >= undercut.reach || surface.relief < undercut.centre + test_notch_extent(undercut) + metres_to_position_units(3) / 2 {
					continue
				}
				return point, undercut, true
			}
		}
	}
	return
}

// The tunnel's and the chamber's distances at a sample apart, as
// cave_distance takes them, without the lakes.
test_cave_parts :: proc(generation: Planet_Generation, cave: Cave_Column, relief: i64, position: World_Position, distance: i64, on_sphere: [3]i64) -> (tunnel, chamber: i64) {
	caves := generation.caves
	height := distance - generation.radius
	strength := cave.strength * cave_shell_fade(caves, relief - height) / NOISE_ONE
	tunnel = cave_tunnel_distance(caves, strength, height - cave.offset, planet_cave_noise(generation, CAVE_TUNNEL_SALT, cast([3]i64)position, caves.tunnel_wavelength_metres))
	chamber = cave_chamber_distance(caves, strength, relief - height, planet_cave_noise(generation, CAVE_CHAMBER_SALT, cave_squashed_point(generation, on_sphere, height), caves.chamber_wavelength_metres))
	return
}

// The march the test steps itself: a spacing at a time up the radial while
// under the relief, roofed at the first ground.
test_full_march :: proc(generation: Planet_Generation, column: Surface_Column, cave: Cave_Column, position: World_Position, distance: i64, on_sphere: [3]i64) -> bool {
	for step := generation.spacing; distance + step - generation.radius < column.relief; step += generation.spacing {
		reach := distance + step
		stepped: World_Position
		for axis in 0 ..< 3 {
			stepped[axis] = position[axis] * reach / distance
		}
		if depth_to_density(sample_depth(generation, column, cave, stepped, reach, on_sphere), generation.spacing_millimetres) > 0 {
			return true
		}
	}
	return false
}

Cave_Scan :: struct {
	open, roofed, tunnel, chamber, deep, wet, unlike: int,
}

// The 64 m square round the point at the generation's spacing, each
// column from 2 m under the shell to the relief.
test_cave_scan :: proc(generation: Planet_Generation, centre: [3]i64) -> (scan: Cave_Scan) {
	up, _ := normalize_fixed(centre)
	forward := tangent_of(up, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, up)
	half := metres_to_position_units(32) / generation.spacing
	shell := metres_to_position_units(i64(generation.caves.shell_metres))
	dry := generation.sea_radius - generation.radius + metres_to_position_units(i64(generation.caves.dry_metres))
	for ahead in -half ..< half {
		for aside in -half ..< half {
			point := test_cave_ring_point(generation, up, forward, right, ahead, aside)
			column := surface_column(generation, point)
			cave := cave_column(generation, column, point)
			if cave.strength == 0 {
				continue
			}
			direction, _ := normalize_fixed(point)
			for height := column.relief - shell - metres_to_position_units(2); height <= column.relief; height += generation.spacing {
				distance := generation.radius + height
				position := World_Position(fixed_scale(direction, distance))
				if depth_to_density(sample_depth(generation, column, cave, position, distance, point), generation.spacing_millimetres) > 0 || depth_to_density(sample_depth(generation, column, {}, position, distance, point), generation.spacing_millimetres) <= 0 {
					continue
				}
				roofed := carved_air_roofed(generation, column, cave, position, distance, point)
				scan.roofed += roofed ? 1 : 0
				scan.open += roofed ? 0 : 1
				scan.unlike += roofed == test_full_march(generation, column, cave, position, distance, point) ? 0 : 1
				scan.deep += column.relief - height > shell ? 1 : 0
				scan.wet += height < dry ? 1 : 0
				tunnel, chamber := test_cave_parts(generation, cave, column.relief, position, distance, point)
				scan.tunnel += depth_to_density(tunnel, generation.spacing_millimetres) <= 0 ? 1 : 0
				scan.chamber += depth_to_density(chamber, generation.spacing_millimetres) <= 0 ? 1 : 0
			}
		}
	}
	return
}

// The spring's camera (0314's, test_bound_camera) on the design planet.
test_spring_cave_mouth :: proc(generation: Planet_Generation) -> (open, roofed: Sample_Coordinate) {
	found: bool
	open, roofed, found = test_cave_mouth(generation, test_bound_camera(generation, 79, 151))
	assert(found, "a cave opens round the spring")
	return
}

// Round the spring's mouth some cave air is open and more is roofed, none
// lies deeper than the shell or under the dry level, tunnels and chambers
// both carve, and at 1000 and 2000 mm the march's shortcut gives the full
// march's answer.
@(test)
test_the_caves_open_and_run_under_the_ground :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, design_caves_test_planet(8000), 1000)
	open, _ := test_spring_cave_mouth(generation)
	centre := projected_position(sample_to_world_position(open, 1000), generation.radius)
	scan := test_cave_scan(generation, centre)
	testing.expectf(t, scan.open > 0 && scan.roofed > scan.open, "open %d, roofed %d", scan.open, scan.roofed)
	testing.expect_value(t, scan.deep, 0)
	testing.expect_value(t, scan.wet, 0)
	testing.expectf(t, scan.tunnel > 0 && scan.chamber > 0, "tunnel air %d, chamber air %d", scan.tunnel, scan.chamber)
	testing.expect_value(t, scan.unlike, 0)
	coarse := test_cave_scan(field_grid_generation(generation, 2), centre)
	testing.expect(t, coarse.open + coarse.roofed > 0, "the 2 m grid holds cave air")
	testing.expect_value(t, coarse.unlike, 0)
}

// Within the calm circle no column has a cave share or a notch and no
// cave reaches under it.
@(test)
test_no_cave_lies_in_the_calm_circle :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, design_caves_test_planet(8000), 1000)
	up, _ := normalize_fixed(generation.landform_home)
	forward := tangent_of(up, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, up)
	calm := metres_to_position_units(i64(generation.landforms.calm_metres))
	for quarter in i64(1) ..= 3 {
		for index in i32(0) ..< 64 {
			angle := index * ANGLE_UNITS_PER_TURN / 64
			offset := calm * quarter / 4
			point := generation.landform_home + fixed_scale(forward, offset * fixed_cosine(angle) / UNIT_VECTOR_ONE) + fixed_scale(right, offset * fixed_sine(angle) / UNIT_VECTOR_ONE)
			point = project_onto_sphere(World_Position(point), vector_length(point), generation.radius)
			column := uncratered_column(generation, point)
			testing.expect_value(t, column.cave_share, 0)
			testing.expect_value(t, column.undercut.reach, 0)
			direction, _ := normalize_fixed(point)
			for under in ([3]i64{1, 8, 24}) {
				distance := generation.radius + column.relief - metres_to_position_units(under)
				testing.expect_value(t, cave_distance(generation, cave_column(generation, column, point), column.relief, World_Position(fixed_scale(direction, distance)), distance, point), CAVE_NONE)
			}
		}
	}
}

// Caves inside their bounds dense enough to reach a lake's water: in every
// region, wherever the presence noise lies, over the sea and with wide
// chambers.
DENSE_TEST_CAVES :: Planet_Caves {
	region_caves_percent        = {100, 100, 100, 100, 100, 100, 100, 100, 100},
	shell_metres                = 32,
	dry_metres                  = 0,
	presence_wavelength_metres  = 420,
	presence_threshold_percent  = -100,
	level_metres                = 18,
	level_wavelength_metres     = 520,
	level_swing_metres          = 9,
	tunnel_wavelength_metres    = 96,
	tunnel_width_millimetres    = 2400,
	tunnel_height_millimetres   = 1600,
	chamber_wavelength_metres   = 56,
	chamber_threshold_percent   = 10,
	roof_metres                 = 8,
	undercut_wavelength_metres  = 40,
	undercut_threshold_percent  = -20,
	undercut_reach_millimetres  = 3000,
	undercut_height_millimetres = 2000,
}

// The kept lakes of the tiles within 1500 m of the home, nearest first by
// their bound centre's chord to the home, the first count; cloned from the
// temp allocator's listing into the allocator, masks and all, which the
// caller deletes with the array.
test_nearest_lakes :: proc(generation: Planet_Generation, cache: ^Water_Tile_Cache, count: int, allocator := context.allocator) -> [dynamic]Planet_Lake {
	home_direction, _ := normalize_fixed(generation.landform_home)
	lakes := clone_planet_lakes(water_tile_lakes_near(cache, home_direction, metres_to_position_units(1500)), allocator)
	defer delete(lakes, allocator)
	home := generation.landform_home
	for first in 0 ..< len(lakes) {
		for second in first + 1 ..< len(lakes) {
			if squared_chord(lakes[second].bound_centre, home) < squared_chord(lakes[first].bound_centre, home) {
				lakes[first], lakes[second] = lakes[second], lakes[first]
			}
		}
	}
	nearest := make([dynamic]Planet_Lake, allocator)
	for lake, index in lakes {
		if index < count {
			append(&nearest, lake)
		} else {
			delete(lake.mask, allocator)
		}
	}
	return nearest
}

// The chunks at the generation's spacing holding the points 1 m and 6 m
// under the lake's level over its mask's shore cells (set, with an unset
// 4-neighbour), distinct, in the mask's row order, then most of them
// spread evenly (temp allocator).
test_lake_shore_chunks :: proc(generation: Planet_Generation, lake: Planet_Lake, most: int) -> [dynamic]Field_Chunk_Coordinate {
	plane := planet_lake_plane(lake, generation.radius, metres_to_position_units(LAKE_CELL_METRES))
	shore := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	for v in -lake.half ..= lake.half {
		for u in -lake.half ..= lake.half {
			if !planet_lake_mask_bit(lake, u, v) || (planet_lake_mask_bit(lake, u + 1, v) && planet_lake_mask_bit(lake, u - 1, v) && planet_lake_mask_bit(lake, u, v + 1) && planet_lake_mask_bit(lake, u, v - 1)) {
				continue
			}
			direction := waters_plane_direction(plane, u, v)
			for under in ([2]i64{1, 6}) {
				position := World_Position(fixed_scale(direction, generation.radius + lake.level - metres_to_position_units(under)))
				coordinate := sample_to_field_chunk_coordinate(world_position_to_sample(position, generation.spacing_millimetres))
				if !slice.contains(shore[:], coordinate) {
					append(&shore, coordinate)
				}
			}
		}
	}
	chunks := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	count := min(most, len(shore))
	for index in 0 ..< count {
		append(&chunks, shore[index * len(shore) / count])
	}
	return chunks
}

// The least squared gap on the plane from the point to a set cell's
// square over every cell of the mask, at most reach squared.
test_mask_scan_squared_distance :: proc(lake: Planet_Lake, east, north, step, reach: i64) -> i64 {
	best := reach * reach
	for v in -lake.half ..= lake.half {
		for u in -lake.half ..= lake.half {
			if planet_lake_mask_bit(lake, u, v) {
				gap_u := max(abs(east - u * step) - step / 2, 0)
				gap_v := max(abs(north - v * step) - step / 2, 0)
				best = min(best, gap_u * gap_u + gap_v * gap_v)
			}
		}
	}
	return best
}

// The sample on the radial through the 1 m plane's point of the lake at a
// height over the radius: its position, distance and point on the sphere.
test_lake_plane_sample :: proc(generation: Planet_Generation, lake: Planet_Lake, east_metres, north_metres, height: i64) -> (position: World_Position, distance: i64, on_sphere: [3]i64) {
	direction := waters_plane_direction(planet_lake_plane(lake, generation.radius, metres_to_position_units(1)), east_metres, north_metres)
	distance = generation.radius + height
	position = World_Position(fixed_scale(direction, distance))
	on_sphere = project_onto_sphere(position, vector_length(cast([3]i64)position), generation.radius)
	return
}

// The mask's distance and run against a scan of every cell on hashed
// masks; then the water's distance and the fade at a hand-made lake of 3
// by 3 cells.
@(test)
test_the_lake_mask_distance_matches_a_scan_of_every_cell :: proc(t: ^testing.T) {
	step := metres_to_position_units(LAKE_CELL_METRES)
	reach := metres_to_position_units(16)
	unlike_distances, unlike_bits := 0, 0
	for trial in 0 ..< 40 {
		half := i64(3 + trial % 20)
		side := 2 * half + 1
		lake := Planet_Lake {
			half = half,
			mask = make([]u64, (side * side + 63) / 64, context.temp_allocator),
		}
		share := test_bound_hash(339, trial, 60)
		for v in -half ..= half {
			for u in -half ..= half {
				if test_bound_hash(340 + trial, int((v + half) * side + u + half), 100) < share {
					set_planet_lake_mask_bit(&lake, u, v)
				}
			}
		}
		span := (half + 12) * step
		for point in 0 ..< 400 {
			east := test_bound_hash(400 + trial, 2 * point, 2 * span + 1) - span
			north := test_bound_hash(400 + trial, 2 * point + 1, 2 * span + 1) - span
			if planet_lake_mask_squared_distance(lake, east, north, step, reach) != test_mask_scan_squared_distance(lake, east, north, step, reach) {
				unlike_distances += 1
			}
		}
		for row in 0 ..< 200 {
			v := test_bound_hash(500 + trial, 3 * row, side) - half
			first := test_bound_hash(500 + trial, 3 * row + 1, side) - half
			last := first + test_bound_hash(500 + trial, 3 * row + 2, min(64, half - first + 1))
			run := planet_lake_mask_run(lake, first, last, v)
			for u in first ..= last {
				bit := (run >> uint(u - first)) & 1 != 0
				if bit != planet_lake_mask_bit(lake, u, v) {
					unlike_bits += 1
				}
			}
		}
		free_all(context.temp_allocator)
	}
	testing.expect_value(t, unlike_distances, 0)
	testing.expect_value(t, unlike_bits, 0)

	generation := make_planet_generation(DEFAULT_WORLD_SEED, shipped_test_home_at(8000), 1000)
	pit := test_bound_direction(339)
	east, north := planet_tangents(pit)
	half := i64(8)
	side := 2 * half + 1
	lake := Planet_Lake {
		centre = pit,
		east   = east,
		north  = north,
		origin = fixed_scale(pit, generation.radius),
		level  = metres_to_position_units(10),
		floor  = metres_to_position_units(8),
		half   = half,
		cells  = 9,
		mask   = make([]u64, (side * side + 63) / 64, context.temp_allocator),
	}
	for v in i64(-1) ..= 1 {
		for u in i64(-1) ..= 1 {
			set_planet_lake_mask_bit(&lake, u, v)
		}
	}
	lake.bound_centre = fixed_scale(pit, generation.radius + lake.level)
	lake.bound_radius = (half + 1) * step * 3 / 2 + (lake.level - lake.floor) + metres_to_position_units(2)
	listed := generation
	listed.lakes = []Planet_Lake{lake}
	listed.water_tiles = nil
	under := lake.level - metres_to_position_units(1)
	position, distance, on_sphere := test_lake_plane_sample(generation, lake, 0, 0, under)
	testing.expect_value(t, planet_lake_water_distance(lake, generation.radius, distance, on_sphere, reach), 0)
	testing.expect_value(t, cave_lake_fade(listed, position, distance, on_sphere), 0)
	position, distance, on_sphere = test_lake_plane_sample(generation, lake, 7, 0, under)
	water := planet_lake_water_distance(lake, generation.radius, distance, on_sphere, reach)
	testing.expectf(t, abs(water - metres_to_position_units(4)) <= 4, "7 m east: %d units from the water", water)
	position, distance, on_sphere = test_lake_plane_sample(generation, lake, 13, 0, under)
	fade := cave_lake_fade(listed, position, distance, on_sphere)
	testing.expectf(t, abs(fade - NOISE_ONE / 2) <= 8, "13 m east: the fade %d", fade)
	above := generation.radius + lake.level + metres_to_position_units(10)
	position = World_Position(fixed_scale(pit, above))
	on_sphere = project_onto_sphere(position, vector_length(cast([3]i64)position), generation.radius)
	testing.expect_value(t, planet_lake_water_distance(lake, generation.radius, above, on_sphere, reach), metres_to_position_units(10))
	testing.expect_value(t, cave_lake_fade(listed, position, above, on_sphere), NOISE_ONE / 2)
	position, distance, on_sphere = test_lake_plane_sample(generation, lake, 6, 6, under)
	water = planet_lake_water_distance(lake, generation.radius, distance, on_sphere, reach)
	diagonal := i64(integer_square_root(u64(18 * metres_to_position_units(1) * metres_to_position_units(1))))
	testing.expectf(t, abs(water - diagonal) <= 4, "6 m east and north: %d units from the water, the root %d", water, diagonal)
	position, distance, on_sphere = test_lake_plane_sample(generation, lake, 23, 0, under)
	testing.expect_value(t, cave_lake_fade(listed, position, distance, on_sphere), NOISE_ONE)
	position, distance, on_sphere = test_lake_plane_sample(generation, lake, 60, 0, under)
	offset := cast([3]i64)position - lake.bound_centre
	testing.expect(t, vector_length(offset) > lake.bound_radius + reach, "60 m east lies past the bound and the reach")
	testing.expect_value(t, cave_lake_fade(listed, position, distance, on_sphere), NOISE_ONE)
	free_all(context.temp_allocator)
}

// The three lakes nearest the home with dense caves, at their shores: the
// same bytes generated in two orders from fresh tiles; cave air inside
// 0327's bound plus the margin; no changed water a spacing or more over
// the sea and no cave air within the margin less a spacing of such water.
@(test) // slow
test_the_caves_leave_the_lakes :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	planet.caves = DENSE_TEST_CAVES
	testing.expect_value(t, caves_problem(planet.caves, planet.landforms), "")
	planet.water_tiles = make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(planet.water_tiles)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	nearest := test_nearest_lakes(generation, planet.water_tiles, 3)
	defer {
		for lake in nearest {
			delete(lake.mask)
		}
		delete(nearest)
	}
	testing.expectf(t, len(nearest) == 3, "%d lakes near the home", len(nearest))
	chunks := make([dynamic]Field_Chunk_Coordinate)
	defer delete(chunks)
	for lake in nearest {
		for coordinate in test_lake_shore_chunks(generation, lake, 8) {
			if !slice.contains(chunks[:], coordinate) {
				append(&chunks, coordinate)
			}
		}
		free_all(context.temp_allocator)
	}
	without := planet
	without.caves = {}
	first_order := planet
	first_order.water_tiles = make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(first_order.water_tiles)
	second_order := planet
	second_order.water_tiles = make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(second_order.water_tiles)
	first := make([]Field_Chunk, len(chunks))
	defer delete(first)
	second := make([]Field_Chunk, len(chunks))
	defer delete(second)
	for coordinate, index in chunks {
		generate_field_chunk(DEFAULT_WORLD_SEED, first_order, 1000, coordinate, &first[index])
		free_all(context.temp_allocator)
	}
	#reverse for coordinate, index in chunks {
		generate_field_chunk(DEFAULT_WORLD_SEED, second_order, 1000, coordinate, &second[index])
		free_all(context.temp_allocator)
	}
	margin := metres_to_position_units(CAVE_LAKE_MARGIN_METRES)
	waters := make(map[Sample_Coordinate]struct{})
	defer delete(waters)
	caves := make([dynamic]Sample_Coordinate)
	defer delete(caves)
	inside, water_changed, sea_changed, order_changed := 0, 0, 0, 0
	plain := new(Field_Chunk)
	defer free(plain)
	for coordinate, index in chunks {
		plain^ = {}
		generate_field_chunk(DEFAULT_WORLD_SEED, without, 1000, coordinate, plain)
		free_all(context.temp_allocator)
		caved := &first[index]
		if caved.density != second[index].density || caved.material != second[index].material || caved.tint != second[index].tint || caved.water != second[index].water || caved.sky_light != second[index].sky_light {
			order_changed += 1
		}
		origin := field_chunk_origin(coordinate)
		for sample in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			at := origin + Sample_Coordinate(field_index_to_local(sample))
			position := sample_to_world_position(at, 1000)
			high := vector_length(cast([3]i64)position) - generation.sea_radius >= generation.spacing
			if caved.water[sample] != plain.water[sample] {
				water_changed += high ? 1 : 0
				sea_changed += high ? 0 : 1
			}
			if high && caved.water[sample] > 0 {
				waters[at] = {}
			}
			if caved.density[sample] > 0 || plain.density[sample] <= 0 {
				continue
			}
			append(&caves, at)
			for lake in nearest {
				offset := cast([3]i64)position - lake.bound_centre
				reach := lake.bound_radius + margin
				if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= reach * reach {
					inside += 1
					break
				}
			}
		}
	}
	reach := i32(16)
	least, near := reach * reach + 1, 0
	for sample in caves {
		best := reach * reach + 1
		for z in -reach ..= reach {
			for y in -reach ..= reach {
				for x in -reach ..= reach {
					squared := x * x + y * y + z * z
					if squared >= best {
						continue
					}
					if _, found := waters[sample + {x, y, z}]; found {
						best = squared
					}
				}
			}
		}
		least = min(least, best)
		near += best <= reach * reach ? 1 : 0
	}
	log.infof("0339: %d shore chunks of the three lakes nearest the home hold %d samples of cave air, %d inside 0327's bounds plus the margin; the nearest lies %.1f m from lake water, %d within 16 m; %d water samples under a spacing over the sea differ (the sea in cave air)", len(chunks), len(caves), inside, math.sqrt(f64(least)), near, sea_changed)
	testing.expectf(t, inside > 0, "%d samples of cave air inside the lakes' old bounds", inside)
	testing.expect_value(t, water_changed, 0)
	testing.expect_value(t, order_changed, 0)
	closest := i32((CAVE_LAKE_MARGIN_METRES * MILLIMETRES_PER_METRE - generation.spacing_millimetres) / generation.spacing_millimetres)
	testing.expectf(t, least >= closest * closest, "cave air lies %d samples squared from lake water", least)
}

// The 27 chunks round a lake's pit at 1 m under bodies, all at once, each
// generated on fresh temp memory, settled for at most 600 ticks.
test_settled_lake_world :: proc(planet: Planet, centre: Field_Chunk_Coordinate, tuning: Field_Water_Tuning) -> (world: Field_World, ticks: int) {
	world.water_model = .Bodies
	world.water_planet = make_field_water_planet(DEFAULT_WORLD_SEED, planet, 1000)
	make_sea_water_body(&world)
	for z in i32(-1) ..= 1 {
		for y in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				chunk := new(Field_Chunk)
				generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, centre + {x, y, z}, chunk)
				field_world_insert_chunk(&world, chunk)
				free_all(context.temp_allocator)
			}
		}
	}
	tick: u64 = 0
	ticks = settle_body_test_water(&world, tuning, &tick, 600)
	return
}

// 0312's lake at 72.02, 143.04 settles with the dense caves round it as
// without them, and holds the same water a spacing or more over the sea.
@(test) // slow
test_a_lake_settles_beside_dense_caves :: proc(t: ^testing.T) {
	planet := waters_test_planet(8000)
	planet.water_features = make_planet_water_features(DEFAULT_WORLD_SEED, planet)
	defer destroy_planet_water_features(&planet.water_features)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	tuning := make_field_water_tuning(test_field_game_config().field_water)
	index := waters_test_lake_near(planet.water_features.lakes, 72.02, 143.04)
	testing.expect(t, index >= 0, "a lake lies at 72.02, 143.04")
	if index < 0 {
		return
	}
	centre := shipped_lake_centre_chunk(generation, planet.water_features.lakes[index])
	caved_planet := planet
	caved_planet.caves = DENSE_TEST_CAVES
	plain_planet := planet
	plain_planet.caves = {}
	caved, caved_ticks := test_settled_lake_world(caved_planet, centre, tuning)
	defer destroy_field_world(&caved)
	plain, plain_ticks := test_settled_lake_world(plain_planet, centre, tuning)
	defer destroy_field_world(&plain)
	testing.expectf(t, caved_ticks < 600 && !any_water_awake(&caved), "with the caves the lake settles (%d ticks)", caved_ticks)
	testing.expect_value(t, still_unowned_water_samples(&caved), 0)
	testing.expectf(t, plain_ticks < 600 && !any_water_awake(&plain), "without the caves the lake settles (%d ticks)", plain_ticks)
	testing.expect_value(t, still_unowned_water_samples(&plain), 0)
	cave_air, high_differ, low_differ := 0, 0, 0
	for coordinate, chunk in caved.chunks {
		other := plain.chunks[coordinate]
		origin := field_chunk_origin(coordinate)
		for sample in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			cave_air += chunk.density[sample] <= 0 && other.density[sample] > 0 ? 1 : 0
			if chunk.water[sample] == other.water[sample] {
				continue
			}
			position := sample_to_world_position(origin + Sample_Coordinate(field_index_to_local(sample)), 1000)
			if vector_length(cast([3]i64)position) - generation.sea_radius >= generation.spacing {
				high_differ += 1
			} else {
				low_differ += 1
			}
		}
	}
	log.infof("0339: the lake at 72.02, 143.04 settles after %d ticks with the dense caves (%d samples of cave air) and %d without; %d samples under a spacing over the sea hold other water (the sea in cave air)", caved_ticks, cave_air, plain_ticks, low_differ)
	testing.expectf(t, cave_air > 0, "%d samples of cave air round the lake", cave_air)
	testing.expect_value(t, high_differ, 0)
}

// 0327's fade from a lake's bound sphere: NOISE_ONE lowered by every lake
// whose bound plus the margin and the fade holds the position.
test_lake_bound_fade :: proc(lakes: []Planet_Lake, position: World_Position) -> i64 {
	margin := metres_to_position_units(CAVE_LAKE_MARGIN_METRES)
	fade_length := metres_to_position_units(CAVE_LAKE_FADE_METRES)
	fade: i64 = NOISE_ONE
	for lake in lakes {
		offset := cast([3]i64)position - lake.bound_centre
		reach := lake.bound_radius + margin + fade_length
		squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
		if squared >= reach * reach {
			continue
		}
		root := i64(integer_square_root(u64(squared)))
		fade = min(fade, clamp((root - lake.bound_radius - margin) * NOISE_ONE / fade_length, 0, NOISE_ONE))
	}
	return fade
}

// The land within 1500 m of the home at 8 km with a cave share that the
// lakes leave to the caves 4 m under the relief, on a 20 m grid: by their
// water against 0327's bound.
@(test) // slow
test_the_lakes_leave_the_land_to_the_caves :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	planet.water_tiles = make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(planet.water_tiles)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	up, _ := normalize_fixed(generation.landform_home)
	lakes := clone_planet_lakes(water_tile_lakes_near(planet.water_tiles, up, metres_to_position_units(1900)))
	free_all(context.temp_allocator)
	defer {
		for lake in lakes {
			delete(lake.mask)
		}
		delete(lakes)
	}
	listed := generation
	listed.lakes = lakes
	listed.water_tiles = nil
	forward := tangent_of(up, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, up)
	dry := generation.sea_radius - generation.radius + metres_to_position_units(i64(planet.caves.dry_metres))
	under := metres_to_position_units(4)
	step := i64(20)
	half := 1500 / step
	shared, before, after, full_before, full_after, under_lake := 0, 0, 0, 0, 0, 0
	for ahead in -half ..= half {
		for aside in -half ..= half {
			if ahead * ahead + aside * aside > half * half {
				continue
			}
			point := fixed_scale(up, generation.radius) + fixed_scale(forward, metres_to_position_units(ahead * step)) + fixed_scale(right, metres_to_position_units(aside * step))
			point = project_onto_sphere(World_Position(point), vector_length(point), generation.radius)
			column := surface_column(listed, point)
			if level, found := planet_lake_level_at(lakes, point, generation.radius); found && column.relief < level {
				under_lake += 1
			}
			if column.relief < dry || column.cave_share <= 0 {
				continue
			}
			direction, _ := normalize_fixed(point)
			distance := generation.radius + column.relief - under
			position := World_Position(fixed_scale(direction, distance))
			old_fade := test_lake_bound_fade(lakes, position)
			new_fade := cave_lake_fade(listed, position, distance, point)
			shared += 1
			before += old_fade > 0 ? 1 : 0
			after += new_fade > 0 ? 1 : 0
			full_before += old_fade == NOISE_ONE ? 1 : 0
			full_after += new_fade == NOISE_ONE ? 1 : 0
		}
		free_all(context.temp_allocator)
	}
	percent :: proc(count, total: int) -> f64 {
		return 100 * f64(count) / f64(max(total, 1))
	}
	log.infof("0339: within 1500 m of the home at 8 km the lakes leave %.1f percent of the land with a cave share to the caves (0327's bound %.1f), %.1f percent at full strength (%.1f), of %d land columns with a share, %d under a lake's level", percent(after, shared), percent(before, shared), percent(full_after, shared), percent(full_before, shared), shared, under_lake)
	testing.expectf(t, shared > 0 && after * 100 >= 95 * shared, "%d of %d columns left to the caves", after, shared)
	testing.expectf(t, after > before, "%d columns left to the caves, %d under 0327's bound", after, before)
}

// Marches up from cave air by the lakes within 900 m of the home with the
// dense caves, every step reading the generation: the fade reads the
// tiles' lakes in place, so no march clones a mask (0327's listing took 42
// and 151 KB a march at 1000 and 333 mm).
@(test) // slow
test_a_march_by_a_lake_copies_no_lake :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	planet.caves = DENSE_TEST_CAVES
	planet.water_tiles = make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(planet.water_tiles)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	lakes := test_nearest_lakes(generation, planet.water_tiles, max(int))
	defer {
		for lake in lakes {
			delete(lake.mask)
		}
		delete(lakes)
	}
	near := metres_to_position_units(900)
	smallest_mask := max(int)
	chunks := make([dynamic]Field_Chunk_Coordinate)
	defer delete(chunks)
	for lake in lakes {
		if squared_chord(lake.bound_centre, generation.landform_home) > near * near {
			continue
		}
		smallest_mask = min(smallest_mask, len(lake.mask) * 8)
		for coordinate in test_lake_shore_chunks(generation, lake, 6) {
			if !slice.contains(chunks[:], coordinate) {
				append(&chunks, coordinate)
			}
		}
		free_all(context.temp_allocator)
	}
	without := planet
	without.caves = {}
	caved := new(Field_Chunk)
	defer free(caved)
	plain := new(Field_Chunk)
	defer free(plain)
	positions := make([dynamic]World_Position)
	defer delete(positions)
	for coordinate in chunks {
		if len(positions) >= 40 {
			break
		}
		caved^ = {}
		plain^ = {}
		generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate, caved)
		generate_field_chunk(DEFAULT_WORLD_SEED, without, 1000, coordinate, plain)
		free_all(context.temp_allocator)
		origin := field_chunk_origin(coordinate)
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if len(positions) < 40 && caved.density[index] <= 0 && plain.density[index] > 0 {
				append(&positions, sample_to_world_position(origin + Sample_Coordinate(field_index_to_local(index)), 1000))
			}
		}
	}
	testing.expectf(t, len(positions) > 0, "%d samples of cave air by the lakes", len(positions))
	world: Field_World
	for spacing_millimetres in ([2]int{1000, 333}) {
		marching := make_planet_generation(DEFAULT_WORLD_SEED, planet, spacing_millimetres)
		most, total, largest: int
		for position in positions {
			tracking: mem.Tracking_Allocator
			mem.tracking_allocator_init(&tracking, context.temp_allocator)
			saved := context.temp_allocator
			context.temp_allocator = mem.tracking_allocator(&tracking)
			field_sky_is_open(&world, marching, world_position_to_sample(position, spacing_millimetres))
			context.temp_allocator = saved
			for _, entry in tracking.allocation_map {
				largest = max(largest, entry.size)
			}
			most = max(most, int(tracking.total_memory_allocated))
			total += int(tracking.total_memory_allocated)
			mem.tracking_allocator_destroy(&tracking)
			free_all(context.temp_allocator)
		}
		log.infof("0339: %d marches by the lakes at %d mm take at most %d bytes, %d on average, the largest allocation %d bytes (a mask %d)", len(positions), spacing_millimetres, most, total / max(len(positions), 1), largest, smallest_mask)
		testing.expectf(t, largest < smallest_mask, "at %d mm an allocation of %d bytes, a mask %d", spacing_millimetres, largest, smallest_mask)
		// The whole march under one mask's bytes: a mask cloned and freed
		// again would not stand in the live allocations above.
		testing.expectf(t, most < smallest_mask, "at %d mm a march takes %d bytes, a mask %d", spacing_millimetres, most, smallest_mask)
	}
}

// The overhang at the nearest notch of a gorge's wall and of a mesa's
// cliff: air at the notch's centre, roofed, and ground 1 m over its top.
@(test) // slow
test_the_walls_overhang :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, design_caves_test_planet(8000), 1000)
	for kind in Notch_Kind {
		point, notch, found := test_nearest_notch(generation, kind)
		testing.expectf(t, found, "a notch of a %v's wall", kind)
		if !found {
			continue
		}
		direction, _ := normalize_fixed(point)
		column := surface_column(generation, point)
		cave := cave_column(generation, column, point)
		inside := generation.radius + notch.centre
		position := World_Position(fixed_scale(direction, inside))
		testing.expectf(t, depth_to_density(sample_depth(generation, column, cave, position, inside, point), 1000) <= 0, "%v: air at the notch's centre", kind)
		testing.expectf(t, carved_air_roofed(generation, column, cave, position, inside, point), "%v: the notch is roofed", kind)
		over := inside + test_notch_extent(notch) + metres_to_position_units(1)
		testing.expectf(t, depth_to_density(sample_depth(generation, column, cave, World_Position(fixed_scale(direction, over)), over, point), 1000) > 0, "%v: ground over the notch", kind)
	}
}

// The spring's mouth: its chunk generates the same bytes and light twice,
// the roofed sample without sky; the fill over the chunks round it lights
// it dimmer than the open sky, and its node's faces pointing down take no
// grass and less than the open sky's light (0380).
@(test) // slow
test_the_fill_lights_a_cave_from_its_mouth :: proc(t: ^testing.T) {
	planet := design_caves_test_planet(8000)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	_, roofed := test_spring_cave_mouth(generation)
	coordinate := sample_to_field_chunk_coordinate(roofed)
	first := new(Field_Chunk, context.temp_allocator)
	second := new(Field_Chunk, context.temp_allocator)
	generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate, first)
	generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate, second)
	testing.expect(t, first.density == second.density && first.material == second.material && first.tint == second.tint, "the chunk generates the same bytes")
	testing.expect(t, first.sky_light == second.sky_light && first.block_light == second.block_light, "the chunk generates the same light")
	index := sample_to_field_index(roofed)
	testing.expect(t, first.density[index] <= 0, "the roofed sample is air")
	testing.expect_value(t, first.sky_light[index], 0)
	testing.expect(t, first.generated_shade, "the chunk holds shade")
	world: Field_World
	defer destroy_field_world(&world)
	for z in i32(-1) ..= 1 {
		for y in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				chunk := new(Field_Chunk)
				generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate + {x, y, z}, chunk)
				field_world_insert_chunk(&world, chunk)
			}
		}
	}
	seed_arrived_field_chunks(&world, max(int))
	run_test_light(&world, make_field_light_tuning(test_lighting_file(), 1000))
	sky := field_world_get_light(&world, roofed, .Sky)
	testing.expectf(t, sky >= 1 && sky < FIELD_LIGHT_FULL, "the sky in the cave is %d", sky)
	// Work item 0380: the node meshed as the finest level does. Its open
	// ground holds the full sky light, so field.fs lights it as before;
	// the faces pointing down under the roof take no grass and hold less,
	// so field.fs greys their bounce, wholly at roof_sky_light_shut.
	shut, shut_found := shader_float_constant(#load("../data/shaders/field.fs", string), "roof_sky_light_shut")
	testing.expect(t, shut_found, "field.fs holds roof_sky_light_shut")
	grid := look_test_grid(&world, coordinate)
	mesh := mesh_field_grid(grid, planet.palette, 1000, {}, context.temp_allocator, make_field_ground_look(generation, planet), true)
	origin_position := sample_to_world_position(field_chunk_origin(coordinate), 1000)
	origin := [3]f64{f64(origin_position.x), f64(origin_position.y), f64(origin_position.z)} / POSITION_UNITS_PER_METRE
	open, downward, grassy, shaded := 0, 0, 0, 0
	for position, vertex in mesh.positions {
		sky_light := mesh.colors[vertex].a
		open += int(sky_light == FIELD_LIGHT_FULL)
		up := linalg.normalize(origin + linalg.to_f64(position))
		facing := linalg.dot(linalg.to_f64(mesh.normals[vertex]), up)
		if facing >= -0.5 {
			continue
		}
		downward += 1
		testing.expectf(t, sky_light < FIELD_LIGHT_FULL, "a face pointing down holds the open sky's light at %v", position)
		shaded += int(sky_light >= 1 && f32(sky_light) <= shut)
		weights: [FIELD_TEXTURED_MATERIAL_COUNT]f32
		for slot in 0 ..< 4 {
			weights[slot] = mesh.weights[vertex][slot]
		}
		ores := unpack_test_bytes(mesh.lights[vertex][1])
		weights[4], weights[5], weights[6] = ores.x, ores.y, ores.z
		look := unpack_test_bytes(mesh.looks[vertex][1])
		grassy += int(cover_ground_shares(weights, look.x, look.y, f32(1 - facing))[.Grass] > 0)
	}
	testing.expect(t, open > 0, "the node holds open ground")
	testing.expect(t, downward > 0, "the node holds faces pointing down")
	testing.expect_value(t, grassy, 0)
	testing.expect(t, shaded > 0, "a face pointing down holds a sky light from 1 to roof_sky_light_shut")
}

// The grids coarser than 2 m have no caves.
@(test)
test_a_coarse_grid_has_no_caves :: proc(t: ^testing.T) {
	for spacing in ([2]int{1000, 500}) {
		generation := make_planet_generation(DEFAULT_WORLD_SEED, design_caves_test_planet(8000), spacing)
		for step in ([4]i32{1, 2, 4, 8}) {
			kept := spacing * int(step) <= CAVE_GRID_MOST_SPACING_MILLIMETRES
			testing.expectf(t, (field_grid_generation(generation, step).caves != {}) == kept, "%d mm at step %d", spacing, step)
		}
	}
}

// The box of the square of half the metres on the tangent plane at a
// point on the sphere, round the square's corners and centre on the
// sphere, widened by 2 m.
test_tangent_square_box :: proc(generation: Planet_Generation, centre: [3]i64, half_metres: i64) -> (minimum, maximum: [3]i64) {
	up, _ := normalize_fixed(centre)
	forward := tangent_of(up, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, up)
	half := metres_to_position_units(half_metres)
	minimum, maximum = centre, centre
	for corner in 0 ..< 4 {
		point := centre + fixed_scale(forward, corner & 1 == 0 ? -half : half) + fixed_scale(right, corner & 2 == 0 ? -half : half)
		point = project_onto_sphere(World_Position(point), vector_length(point), generation.radius)
		for axis in 0 ..< 3 {
			minimum[axis] = min(minimum[axis], point[axis])
			maximum[axis] = max(maximum[axis], point[axis])
		}
	}
	widen := metres_to_position_units(2)
	return minimum - widen, maximum + widen
}

// No tree of the spring's 224 m square stands over air 1 m under its
// relief.
@(test)
test_no_tree_stands_over_a_cave :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, shipped_test_home_at(8000), 1000)
	minimum, maximum := test_tangent_square_box(generation, test_degree_point(generation, 79, 151), 112)
	trees := planet_trees_in_box(&generation, minimum, maximum)
	testing.expect(t, len(trees) > 0, "trees stand round the spring")
	over_air := 0
	for tree in trees {
		on_sphere := tree_test_on_sphere(generation, tree)
		up, _ := normalize_fixed(on_sphere)
		distance := generation.radius + surface_relief(generation, on_sphere) - metres_to_position_units(1)
		if planet_sample(generation, World_Position(fixed_scale(up, distance))).density <= 0 {
			over_air += 1
		}
	}
	testing.expect_value(t, over_air, 0)
}

// A world.sjson recorded before the caves (its caves 0, as a file of
// before reads them), loaded against data that has them: one log line, no
// caves and the ground of before at the spring's cave mouth.
@(test)
test_a_world_file_before_the_caves_keeps_its_ground :: proc(t: ^testing.T) {
	old := design_caves_test_planet(8000)
	old.caves = {}
	caves := design_caves_test_planet(8000)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = old.id},
		planet_generation = planet_generation_record(old),
	}
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect(t, strings.contains(recorded_caves_note(parsed.planet_generation, caves), "records no caves"), "the old file's note")
	testing.expect_value(t, recorded_caves_note(planet_generation_record(caves), caves), "")
	planets := []Planet{caves}
	_, planet, record := resolve_world_planet(parsed.settings, parsed.planet_generation, planets, true)
	recorded := make_recorded_planet(planet, record, context.temp_allocator)
	testing.expect(t, recorded.caves == {}, "the old world has no caves")
	open, _ := test_spring_cave_mouth(make_planet_generation(DEFAULT_WORLD_SEED, caves, 1000))
	coordinate := sample_to_field_chunk_coordinate(open)
	sources := [3]Planet{recorded, old, caves}
	chunks: [3]^Field_Chunk
	for &chunk, index in chunks {
		chunk = new(Field_Chunk, context.temp_allocator)
		generate_field_chunk(DEFAULT_WORLD_SEED, sources[index], 1000, coordinate, chunk)
	}
	testing.expect(t, chunks[0].density == chunks[1].density && chunks[0].material == chunks[1].material && chunks[0].sky_light == chunks[1].sky_light, "the recorded world generates the ground of before")
	testing.expect(t, chunks[0].density != chunks[2].density, "the data's caves would change it")
}

@(test)
test_a_new_world_records_its_caves :: proc(t: ^testing.T) {
	planet := default_planet(shipped_test_planets())
	record := planet_generation_record(planet)
	testing.expect(t, planet.caves != {}, "the shipped home has caves")
	testing.expect_value(t, record.caves, planet.caves)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = planet.id},
		planet_generation = record,
	}
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.planet_generation.caves, planet.caves)
	testing.expect_value(t, make_recorded_planet(planet, parsed.planet_generation, context.temp_allocator).caves, planet.caves)
}

@(test)
test_caves_problems :: proc(t: ^testing.T) {
	landforms := design_landform_test_planet(8000).landforms
	testing.expect_value(t, caves_problem({}, landforms), "")
	testing.expect_value(t, caves_problem(default_planet(shipped_test_planets()).caves, landforms), "")
	testing.expect_value(t, caves_problem(DESIGN_TEST_CAVES, landforms), "")
	testing.expect_value(t, caves_problem(DESIGN_TEST_CAVES, {}), "caves need landforms")
	Case :: struct {
		caves: Planet_Caves,
		key:   string,
	}
	cases := make([dynamic]Case, context.temp_allocator)
	knot := DESIGN_TEST_CAVES
	knot.region_caves_percent[4] = 101
	append(&cases, Case{knot, "region_caves_percent[4]"})
	knot.region_caves_percent[4] = -1
	append(&cases, Case{knot, "region_caves_percent[4]"})
	Bound_Case :: struct {
		key:         string,
		below, over: int,
	}
	bounds := [?]Bound_Case {
		{"shell_metres", CAVE_SHELL_FADE_METRES - 1, MAXIMUM_CAVE_SHELL_METRES + 1},
		{"dry_metres", -1, MAXIMUM_RELIEF_HEIGHT_METRES + 1},
		{"presence_wavelength_metres", 0, MAXIMUM_CAVE_WAVELENGTH_METRES + 1},
		{"presence_threshold_percent", -101, 101},
		{"level_metres", 3, 65},
		{"level_wavelength_metres", 0, MAXIMUM_CAVE_WAVELENGTH_METRES + 1},
		{"level_swing_metres", -1, 19},
		{"tunnel_wavelength_metres", 0, MAXIMUM_CAVE_WAVELENGTH_METRES + 1},
		{"tunnel_width_millimetres", 499, 8001},
		{"tunnel_height_millimetres", 499, 8001},
		{"chamber_wavelength_metres", 0, MAXIMUM_CAVE_WAVELENGTH_METRES + 1},
		{"chamber_threshold_percent", -1, 101},
		{"roof_metres", -1, 33},
		{"undercut_wavelength_metres", 0, MAXIMUM_CAVE_WAVELENGTH_METRES + 1},
		{"undercut_threshold_percent", -101, 101},
		{"undercut_reach_millimetres", 499, 8001},
		{"undercut_height_millimetres", 999, 8001},
	}
	for bound in bounds {
		for value in ([2]int{bound.below, bound.over}) {
			caves := DESIGN_TEST_CAVES
			test_set_cave_key(&caves, bound.key, value)
			append(&cases, Case{caves, bound.key})
		}
	}
	tunnel := DESIGN_TEST_CAVES
	tunnel.tunnel_height_millimetres = 7001
	append(&cases, Case{tunnel, "leaves no rock between levels"})
	roof := DESIGN_TEST_CAVES
	roof.roof_metres = 7
	append(&cases, Case{roof, "leaves no rock between a chamber"})
	undercut := DESIGN_TEST_CAVES
	undercut.undercut_height_millimetres = 1400
	append(&cases, Case{undercut, "is under half the reach"})
	for entry in cases {
		problem := caves_problem(entry.caves, landforms)
		testing.expectf(t, strings.contains(problem, entry.key), "%s: %q", entry.key, problem)
	}
	none := DESIGN_TEST_CAVES
	none.tunnel_width_millimetres = 0
	none.undercut_reach_millimetres = 0
	testing.expect_value(t, caves_problem(none, landforms), "")
}

// Sets the caves' key by its name.
test_set_cave_key :: proc(caves: ^Planet_Caves, key: string, value: int) {
	switch key {
	case "shell_metres":
		caves.shell_metres = value
	case "dry_metres":
		caves.dry_metres = value
	case "presence_wavelength_metres":
		caves.presence_wavelength_metres = value
	case "presence_threshold_percent":
		caves.presence_threshold_percent = value
	case "level_metres":
		caves.level_metres = value
	case "level_wavelength_metres":
		caves.level_wavelength_metres = value
	case "level_swing_metres":
		caves.level_swing_metres = value
	case "tunnel_wavelength_metres":
		caves.tunnel_wavelength_metres = value
	case "tunnel_width_millimetres":
		caves.tunnel_width_millimetres = value
	case "tunnel_height_millimetres":
		caves.tunnel_height_millimetres = value
	case "chamber_wavelength_metres":
		caves.chamber_wavelength_metres = value
	case "chamber_threshold_percent":
		caves.chamber_threshold_percent = value
	case "roof_metres":
		caves.roof_metres = value
	case "undercut_wavelength_metres":
		caves.undercut_wavelength_metres = value
	case "undercut_threshold_percent":
		caves.undercut_threshold_percent = value
	case "undercut_reach_millimetres":
		caves.undercut_reach_millimetres = value
	case "undercut_height_millimetres":
		caves.undercut_height_millimetres = value
	case:
		panic(key)
	}
}
