package game

import "core:log"
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

// Caves inside their bounds dense enough to reach a lake's bound: in every
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

// The chunks across a lake's bound plus the margin: in two directions of
// the bound's centre, the chunks holding the samples 12 m inside and
// outside it at 4 and 20 m under the relief.
test_lake_edge_chunks :: proc(generation: Planet_Generation, lake: Planet_Lake) -> [dynamic]Field_Chunk_Coordinate {
	chunks := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	up, _ := normalize_fixed(lake.bound_centre)
	forward := tangent_of(up, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, up)
	edge := lake.bound_radius + metres_to_position_units(CAVE_LAKE_MARGIN_METRES)
	for direction in ([2][3]i64{forward, right}) {
		for offset in ([2]i64{edge - metres_to_position_units(12), edge + metres_to_position_units(12)}) {
			point := fixed_scale(up, generation.radius) + fixed_scale(direction, offset)
			point = project_onto_sphere(World_Position(point), vector_length(point), generation.radius)
			column_up, _ := normalize_fixed(point)
			relief := surface_relief(generation, point)
			for under in ([2]i64{4, 20}) {
				position := World_Position(fixed_scale(column_up, generation.radius + relief - metres_to_position_units(under)))
				coordinate := sample_to_field_chunk_coordinate(world_position_to_sample(position, 1000))
				if !slice.contains(chunks[:], coordinate) {
					append(&chunks, coordinate)
				}
			}
		}
	}
	return chunks
}

// The three lakes nearest the home with dense caves: no cave at their
// bound plus the margin; across it the chunks hold cave air outside and
// no changed sample inside, no changed water, and the same bytes
// generated in two orders from fresh tiles.
@(test) // slow
test_the_caves_leave_the_lakes :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	planet.caves = DENSE_TEST_CAVES
	testing.expect_value(t, caves_problem(planet.caves, planet.landforms), "")
	planet.water_tiles = make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(planet.water_tiles)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	home_direction, _ := normalize_fixed(generation.landform_home)
	lakes := water_tile_lakes_near(planet.water_tiles, home_direction, metres_to_position_units(1500))
	testing.expectf(t, len(lakes) >= 3, "%d lakes near the home", len(lakes))
	nearest := make([dynamic]Planet_Lake, context.temp_allocator)
	for lake in lakes {
		append(&nearest, lake)
	}
	for first in 0 ..< len(nearest) {
		for second in first + 1 ..< len(nearest) {
			if squared_chord(nearest[second].bound_centre, generation.landform_home) < squared_chord(nearest[first].bound_centre, generation.landform_home) {
				nearest[first], nearest[second] = nearest[second], nearest[first]
			}
		}
	}
	directions := TEST_AXIS_PLANE_DIRECTIONS
	margin := metres_to_position_units(CAVE_LAKE_MARGIN_METRES)
	chunks := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	edges := make([dynamic]Planet_Lake, context.temp_allocator)
	for lake in nearest[:min(3, len(nearest))] {
		for index in 0 ..< 16 {
			direction, _ := normalize_fixed(directions[index + 2] * UNIT_VECTOR_ONE)
			position := World_Position(lake.bound_centre + fixed_scale(direction, lake.bound_radius + margin - 4))
			testing.expectf(t, cave_lake_fade(generation, position) == 0, "the fade at %v by the lake at %v", position, lake.bound_centre)
		}
		for coordinate in test_lake_edge_chunks(generation, lake) {
			append(&chunks, coordinate)
			append(&edges, lake)
		}
	}
	without := planet
	without.caves = {}
	first_order := planet
	first_order.water_tiles = make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(first_order.water_tiles)
	second_order := planet
	second_order.water_tiles = make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(second_order.water_tiles)
	first := make([]Field_Chunk, len(chunks), context.temp_allocator)
	second := make([]Field_Chunk, len(chunks), context.temp_allocator)
	for coordinate, index in chunks {
		generate_field_chunk(DEFAULT_WORLD_SEED, first_order, 1000, coordinate, &first[index])
	}
	#reverse for coordinate, index in chunks {
		generate_field_chunk(DEFAULT_WORLD_SEED, second_order, 1000, coordinate, &second[index])
	}
	cave_air, inside_changed, water_changed, order_changed := 0, 0, 0, 0
	plain := new(Field_Chunk, context.temp_allocator)
	for coordinate, index in chunks {
		generate_field_chunk(DEFAULT_WORLD_SEED, without, 1000, coordinate, plain)
		caved := &first[index]
		if caved.density != second[index].density || caved.material != second[index].material || caved.tint != second[index].tint || caved.water != second[index].water || caved.sky_light != second[index].sky_light {
			order_changed += 1
		}
		lake := edges[index]
		origin := field_chunk_origin(coordinate)
		for sample in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			water_changed += caved.water[sample] != plain.water[sample] ? 1 : 0
			if caved.density[sample] == plain.density[sample] && caved.material[sample] == plain.material[sample] {
				continue
			}
			offset := cast([3]i64)sample_to_world_position(origin + Sample_Coordinate(field_index_to_local(sample)), 1000) - lake.bound_centre
			reach := lake.bound_radius + margin
			if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= reach * reach {
				inside_changed += 1
			} else if caved.density[sample] <= 0 && plain.density[sample] > 0 {
				cave_air += 1
			}
		}
	}
	log.infof("0327: %d chunks across the three lakes' bounds hold %d samples of cave air outside them", len(chunks), cave_air)
	testing.expectf(t, cave_air > 0, "%d samples of cave air across the lakes' bounds", cave_air)
	testing.expect_value(t, inside_changed, 0)
	testing.expect_value(t, water_changed, 0)
	testing.expect_value(t, order_changed, 0)
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
// it dimmer than the open sky.
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
