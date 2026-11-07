package game

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import "core:testing"
@(require) import "core:time"

// Work item 0311: the ground cover's placement on the shipped home at
// 8 km with DEFAULT_WORLD_SEED, on generated level 0 grids meshed with
// the look measuring the cuts and the desktop row.

COVER_TEST_ROW :: Field_Cover_Row {
	distance_percent = 100,
	density_percent  = 100,
	node_limit       = 8192,
}

// The places of the design's probe (tmp/0311 of the design), on the
// ground of main before 0324, 0312 and 0310.
Cover_Test_Spot :: struct {
	name:                string,
	latitude, longitude: f64,
}

COVER_TEST_SPOTS :: [4]Cover_Test_Spot {
	{"meadow", 84.4210, 134.9423},
	{"wet and warm", 69.4842, 134.3802},
	{"dry", 84.3585, 0.3698},
	{"cold", 81.4358, 159.9575},
}

// The unit direction at a latitude and longitude in degrees.
cover_test_direction :: proc(latitude, longitude: f64) -> [3]i64 {
	return planet_direction_at(i32(latitude * ANGLE_UNITS_PER_TURN / 360), i32(longitude * ANGLE_UNITS_PER_TURN / 360))
}

cover_test_setup :: proc() -> (planet: Planet, generation: Planet_Generation) {
	planet = shipped_test_home_at(8000)
	return planet, make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
}

// The finest node holding the surface ahead and aside metres from the
// direction along its north and east tangents.
cover_test_surface_node :: proc(generation: Planet_Generation, direction: [3]i64, ahead, aside: i64) -> Field_Node {
	forward := frame_north_tangent(direction)
	right := fixed_cross(forward, direction)
	point := test_sphere_point(generation, direction, forward, right, ahead, aside)
	surface := point * (generation.radius + uncratered_relief(generation, point)) / generation.radius
	return test_surface_node(World_Position(surface), generation.spacing_millimetres, 0)
}

// The cover of a grid meshed without skirts, the look measuring its cuts,
// and the mesh's area in square metres (temp allocator).
cover_test_grid_cover :: proc(generation: Planet_Generation, planet: Planet, grid: ^Field_Grid, frames: []Cover_Frame = nil, row := COVER_TEST_ROW) -> (data: Field_Cover_Data, area: f32, mesh: Field_Mesh_Data) {
	look := make_field_ground_look(generation, planet)
	table := make_field_cover_table(generation, planet, row)
	mesh = mesh_field_grid(grid, planet.palette, generation.spacing_millimetres, {}, context.temp_allocator, look, true, &data, table, frames)
	for first := 0; first + 2 < len(mesh.indices); first += 3 {
		a, b, c := mesh.positions[mesh.indices[first]], mesh.positions[mesh.indices[first + 1]], mesh.positions[mesh.indices[first + 2]]
		edge_first, edge_second := b - a, c - a
		cross := [3]f32{edge_first.y * edge_second.z - edge_first.z * edge_second.y, edge_first.z * edge_second.x - edge_first.x * edge_second.z, edge_first.x * edge_second.y - edge_first.y * edge_second.x}
		area += math.sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z) / 2
	}
	return data, area, mesh
}

// The node's generated grid's cover (temp allocator).
cover_test_node_cover :: proc(generation: Planet_Generation, planet: Planet, node: Field_Node, frames: []Cover_Frame = nil, row := COVER_TEST_ROW) -> (data: Field_Cover_Data, area: f32) {
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	data, area, _ = cover_test_grid_cover(generation, planet, grid, frames, row)
	return data, area
}

// A kind's index by its id; -1 without it.
cover_test_kind :: proc(planet: Planet, id: string) -> int {
	for kind, index in planet.cover.kinds {
		if kind.id == id {
			return index
		}
	}
	return -1
}

// A node's first sample in metres from the centre.
cover_test_node_origin :: proc(node: Field_Node, spacing_millimetres: int) -> [3]f64 {
	origin := sample_to_world_position(field_node_origin(node), spacing_millimetres)
	return [3]f64{f64(origin.x), f64(origin.y), f64(origin.z)} / POSITION_UNITS_PER_METRE
}

cover_test_vector :: proc(vector: [3]f32) -> [3]f64 {
	return {f64(vector.x), f64(vector.y), f64(vector.z)}
}

// The spot's node and its eight neighbours along the tangent plane, 32 m
// apart, each once: per kind the instances and the surface's area.
cover_test_spot_counts :: proc(generation: Planet_Generation, planet: Planet, spot: Cover_Test_Spot) -> (counts: [MAXIMUM_COVER_KINDS]int, area: f32) {
	direction := cover_test_direction(spot.latitude, spot.longitude)
	seen := make(map[Field_Node]struct{}, context.temp_allocator)
	for ahead in ([3]i64{-32, 0, 32}) {
		for aside in ([3]i64{-32, 0, 32}) {
			node := cover_test_surface_node(generation, direction, ahead, aside)
			if node in seen {
				continue
			}
			seen[node] = {}
			data, node_area := cover_test_node_cover(generation, planet, node)
			area += node_area
			for kind, index in data.kinds {
				counts[index] += len(kind.instances)
			}
		}
	}
	return counts, area
}

// The kinds follow the climate: at the meadow and the wet and warm spot
// grass, flowers and ferns; at the dry one little grass, dry stones and
// no ferns; at the cold one no flowers and less grass.
@(test) // slow
test_the_cover_follows_the_climate :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	grass, flowers, ferns, dry_stones := cover_test_kind(planet, "grass"), cover_test_kind(planet, "flowers"), cover_test_kind(planet, "ferns"), cover_test_kind(planet, "dry_stones")
	spots := COVER_TEST_SPOTS
	for spot in spots {
		counts, area := cover_test_spot_counts(generation, planet, spot)
		testing.expectf(t, area > 1000, "the %s's nodes hold %v square metres", spot.name, area)
		density: [MAXIMUM_COVER_KINDS]f32
		line := strings.builder_make(context.temp_allocator)
		for kind, index in planet.cover.kinds {
			density[index] = f32(counts[index]) / max(area, 1)
			fmt.sbprintf(&line, " %s %.3f", kind.id, density[index])
		}
		log.infof("cover at the %s: %.0f m2, a square metre:%s", spot.name, area, strings.to_string(line))
		switch spot.name {
		case "meadow", "wet and warm":
			testing.expectf(t, density[grass] >= 2.5 && density[grass] <= 6, "the %s holds %v grass a square metre", spot.name, density[grass])
			testing.expectf(t, density[flowers] >= 0.1 && density[flowers] <= 1, "the %s holds %v flowers a square metre", spot.name, density[flowers])
			testing.expectf(t, density[ferns] >= 0.05 && density[ferns] <= 0.8, "the %s holds %v ferns a square metre", spot.name, density[ferns])
		case "dry":
			testing.expectf(t, density[grass] < 0.4, "the dry spot holds %v grass a square metre", density[grass])
			testing.expectf(t, density[dry_stones] > 0.3, "the dry spot holds %v dry stones a square metre", density[dry_stones])
			testing.expect_value(t, counts[ferns], 0)
		case "cold":
			testing.expect_value(t, counts[flowers], 0)
			testing.expectf(t, density[grass] < 2.5, "the cold spot holds %v grass a square metre", density[grass])
		}
	}
}

// A shipped kind as the placement reads it.
cover_test_table_kind :: proc(planet: Planet, id: string) -> Field_Cover_Kind {
	return field_cover_kind(planet.cover.kinds[cover_test_kind(planet, id)])
}

@(test)
test_cover_kind_density_reads_the_ground :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	grass, ferns, boulders, pebbles := cover_test_table_kind(planet, "grass"), cover_test_table_kind(planet, "ferns"), cover_test_table_kind(planet, "boulders"), cover_test_table_kind(planet, "pebbles")
	meadow := Cover_Ground {
		celsius  = 20,
		moisture = 90,
		cut      = 1,
		shares   = #partial [Cover_Surface]f32{.Grass = 1},
	}
	testing.expect_value(t, cover_kind_density(grass, meadow, 1), grass.rate)
	testing.expect(t, cover_kind_density(ferns, meadow, 1) > 0, "ferns grow on the wet meadow")
	testing.expect_value(t, cover_kind_density(grass, meadow, 0.5), grass.rate / 2)
	snow := Cover_Ground {
		celsius  = -5,
		moisture = 70,
		cut      = 1,
		shares   = #partial [Cover_Surface]f32{.Snow = 1},
	}
	testing.expect_value(t, cover_kind_density(grass, snow, 1), 0)
	testing.expect(t, cover_kind_density(boulders, snow, 1) > 0, "boulders lie on the snow")
	face := Cover_Ground {
		celsius       = 12,
		moisture      = 60,
		slope_degrees = 50,
		cut           = 1,
		shares        = #partial [Cover_Surface]f32{.Rock = 1},
	}
	testing.expect(t, cover_kind_density(pebbles, face, 1) > 0, "pebbles lie on a rock face")
	testing.expect_value(t, cover_kind_density(grass, face, 1), 0)
	edge := face
	edge.slope_degrees = 20
	edge.shares = #partial [Cover_Surface]f32{.Rock = 0.5, .Grass = 0.5}
	full := edge
	full.shares = #partial [Cover_Surface]f32{.Rock = 1}
	testing.expectf(t, cover_kind_density(pebbles, edge, 1) > cover_kind_density(pebbles, full, 1), "pebbles gather where rock meets grass: %v against %v", cover_kind_density(pebbles, edge, 1), cover_kind_density(pebbles, full, 1))
	cut := meadow
	cut.cut = 0
	testing.expect_value(t, cover_kind_density(grass, cut, 1), 0)
	// The tents: full inside, half way down the fade, none past it.
	testing.expect_value(t, cover_tent(10, {2, 30}, 6), 1)
	testing.expect_value(t, cover_tent(-1, {2, 30}, 6), 0.5)
	testing.expect_value(t, cover_tent(37, {2, 30}, 6), 0)
	testing.expect_value(t, cover_cut_share(100), 1)
	testing.expect_value(t, cover_cut_share(300), 0.5)
	testing.expect_value(t, cover_cut_share(500), 0)
}

// Möller and Trumbore's ray and triangle: the distance along the unit
// direction to where the ray meets the triangle, with a margin round its
// edges, and the hit's barycentric shares of b (along) and c (across).
cover_test_ray_barycentric :: proc(origin, direction, a, b, c: [3]f64) -> (distance, along, across: f64, hit: bool) {
	edge_first, edge_second := b - a, c - a
	sideways := cover_cross(direction, edge_second)
	determinant := cover_dot(edge_first, sideways)
	if abs(determinant) < 1e-12 {
		return 0, 0, 0, false
	}
	offset := origin - a
	along = cover_dot(offset, sideways) / determinant
	turned := cover_cross(offset, edge_first)
	across = cover_dot(direction, turned) / determinant
	margin := 1e-4
	if along < -margin || across < -margin || along + across > 1 + margin {
		return 0, 0, 0, false
	}
	return cover_dot(edge_second, turned) / determinant, along, across, true
}

cover_test_ray_hit :: proc(origin, direction, a, b, c: [3]f64) -> (distance: f64, hit: bool) {
	distance, _, _, hit = cover_test_ray_barycentric(origin, direction, a, b, c)
	return distance, hit
}

// The meadow node: each of the first 300 instances' base, raised along
// its up by its sink (the sink's share of its height, and up to half its
// width more on a slope), lies on a triangle of the node's surface,
// within 5 mm.
@(test)
test_the_cover_lies_on_its_triangles :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	spots := COVER_TEST_SPOTS
	node := cover_test_surface_node(generation, cover_test_direction(spots[0].latitude, spots[0].longitude), 0, 0)
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	data, _, mesh := cover_test_grid_cover(generation, planet, grid)
	origin := cover_test_node_origin(node, 1000)
	table := make_field_cover_table(generation, planet, COVER_TEST_ROW)
	checked := 0
	for kind, kind_index in data.kinds {
		for instance in kind.instances {
			if checked >= 300 {
				break
			}
			checked += 1
			base := cover_test_vector(cover_instance_base(instance)) - origin
			up := cover_test_vector({instance[0, 1], instance[1, 1], instance[2, 1]})
			height := math.sqrt(cover_dot(up, up))
			width := math.sqrt(f64(instance[0, 0] * instance[0, 0] + instance[1, 0] * instance[1, 0] + instance[2, 0] * instance[2, 0]))
			depth := math.sqrt(f64(instance[0, 2] * instance[0, 2] + instance[1, 2] * instance[1, 2] + instance[2, 2] * instance[2, 2]))
			least := f64(table.kinds[kind_index].sink) * height
			most := least + 0.5 * max(width, depth)
			found := false
			for first := 0; first + 2 < len(mesh.indices); first += 3 {
				a, b, c := cover_test_vector(mesh.positions[mesh.indices[first]]), cover_test_vector(mesh.positions[mesh.indices[first + 1]]), cover_test_vector(mesh.positions[mesh.indices[first + 2]])
				if distance, hit := cover_test_ray_hit(base, up / height, a, b, c); hit && distance >= least - 0.005 && distance <= most + 0.005 {
					found = true
					break
				}
			}
			testing.expectf(t, found, "a %s instance's base %v lies off the surface", planet.cover.kinds[kind_index].id, base)
		}
	}
	testing.expect_value(t, checked, 300)
}

// The instance as a map key.
cover_test_key :: proc(instance: matrix[4, 4]f32) -> [16]f32 {
	return transmute([16]f32)instance
}

// The meadow node meshed twice gives the same cover; with a 1.5 m pit
// carved into its grid (as expect_a_dug_pit_floor_is_not_natural
// carves) every instance more than COVER_TEST_KEPT_METRES from the pit is
// one of the undug cover's, and none stands over the pit's inside, its
// radius less 0.2 m along the ground. The carving reaches samples up to
// a metre past the radius, a moved vertex lies up to a cell's diagonal
// past those and its triangles a quad's further, so instances to about
// 5.6 m may change (3.5 m measured at the shipped seed).
COVER_TEST_KEPT_METRES :: 6
@(test) // slow
test_a_remesh_keeps_the_cover :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	spots := COVER_TEST_SPOTS
	node := cover_test_surface_node(generation, cover_test_direction(spots[0].latitude, spots[0].longitude), 0, 0)
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	first, _, mesh := cover_test_grid_cover(generation, planet, grid)
	second, _, _ := cover_test_grid_cover(generation, planet, grid)
	total := 0
	for kind, index in first.kinds {
		testing.expect(t, slice.equal(kind.instances[:], second.kinds[index].instances[:]), "a remesh moves the cover")
		testing.expect_value(t, kind.rank_counts, second.kinds[index].rank_counts)
		total += len(kind.instances)
	}
	testing.expect(t, total > 1000, "the meadow node holds a cover")
	// The pit round the surface vertex nearest the node's centre.
	pit_radius: f32 = 1.5
	centre := [3]f32{1, 1, 1} * FIELD_GRID_CELLS / 2
	pit := mesh.positions[0]
	for position in mesh.positions {
		if linalg.length(position - centre) < linalg.length(pit - centre) {
			pit = position
		}
	}
	dug := new(Field_Grid, context.temp_allocator)
	dug^ = grid^
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				index := field_grid_index({x, y, z})
				distance := linalg.length([3]f32{f32(x), f32(y), f32(z)} - pit)
				carved := i8(clamp((distance - pit_radius) * DENSITY_STEPS_PER_SAMPLE, -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
				if carved < dug.density[index] {
					dug.density[index] = carved
				}
				if dug.density[index] <= 0 {
					dug.material[index], dug.tint[index] = .Air, 0
				}
			}
		}
	}
	after, _, _ := cover_test_grid_cover(generation, planet, dug)
	origin := cover_test_node_origin(node, 1000)
	pit_centre := cover_test_vector(pit)
	up := cover_normalized(origin + pit_centre, {0, 1, 0})
	farthest_changed: f64 = 0
	compared := 0
	for kind, index in after.kinds {
		before := make(map[[16]f32]struct{}, context.temp_allocator)
		for instance in first.kinds[index].instances {
			before[cover_test_key(instance)] = {}
		}
		for instance in kind.instances {
			offset := cover_test_vector(cover_instance_base(instance)) - origin - pit_centre
			along_ground := offset - up * cover_dot(offset, up)
			testing.expectf(t, math.sqrt(cover_dot(along_ground, along_ground)) >= f64(pit_radius) - 0.2, "a %s instance stands %v m into the pit", planet.cover.kinds[index].id, math.sqrt(cover_dot(along_ground, along_ground)))
			distance := math.sqrt(cover_dot(offset, offset))
			if cover_test_key(instance) not_in before {
				farthest_changed = max(farthest_changed, distance)
				continue
			}
			compared += distance > COVER_TEST_KEPT_METRES ? 1 : 0
		}
	}
	log.infof("the pit changed instances out to %.2f m", farthest_changed)
	testing.expect(t, compared > 500, "the ground beyond the pit keeps its cover")
	for kind in after.kinds {
		for instance in kind.instances {
			offset := cover_test_vector(cover_instance_base(instance)) - origin - pit_centre
			if math.sqrt(cover_dot(offset, offset)) > COVER_TEST_KEPT_METRES {
				found := false
				for index in 0 ..< MAXIMUM_COVER_KINDS {
					if slice.contains(first.kinds[index].instances[:], instance) {
						found = true
						break
					}
				}
				testing.expectf(t, found, "an instance %v m from the pit moved", math.sqrt(cover_dot(offset, offset)))
			}
		}
	}
}

// Ground under water, ground cut past twice COVER_CUT_MILLIMETRES and
// carved air without the sky carry none.
@(test)
test_cut_ground_wet_ground_and_carved_air_carry_no_cover :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	spots := COVER_TEST_SPOTS
	node := cover_test_surface_node(generation, cover_test_direction(spots[0].latitude, spots[0].longitude), 0, 0)
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	dry, _, _ := cover_test_grid_cover(generation, planet, grid)
	testing.expect(t, cover_test_count(dry) > 1000, "the meadow node holds a cover")
	wet := new(Field_Grid, context.temp_allocator)
	wet^ = grid^
	for density, index in wet.density {
		if !field_sample_is_ground(density) {
			wet.water[index] = MAXIMUM_DENSITY
		}
	}
	under_water, _, _ := cover_test_grid_cover(generation, planet, wet)
	testing.expect_value(t, cover_test_count(under_water), 0)
	dark := new(Field_Grid, context.temp_allocator)
	dark^ = grid^
	dark.sky_light = {}
	carved_air, _, _ := cover_test_grid_cover(generation, planet, dark)
	testing.expect_value(t, cover_test_count(carved_air), 0)
	look := make_field_ground_look(generation, planet)
	surface := mesh_field_surface(grid, planet.palette, context.temp_allocator)
	write_field_ground_look(&surface, grid, look, 1000, true)
	for &vertex in surface.vertices {
		vertex.look.offset_millimetres = 2 * COVER_CUT_MILLIMETRES
	}
	table := make_field_cover_table(generation, planet, COVER_TEST_ROW)
	testing.expect_value(t, cover_test_count(place_field_cover(surface, grid, look, table, 1000, nil, context.temp_allocator)), 0)
	// Half way there the cover thins.
	for &vertex in surface.vertices {
		vertex.look.offset_millimetres = 3 * COVER_CUT_MILLIMETRES / 2
	}
	thinned := cover_test_count(place_field_cover(surface, grid, look, table, 1000, nil, context.temp_allocator))
	testing.expectf(t, thinned > 0 && thinned * 10 < cover_test_count(dry) * 7, "%d instances half cut against %d", thinned, cover_test_count(dry))
}

cover_test_count :: proc(data: Field_Cover_Data) -> int {
	count := 0
	for kind in data.kinds {
		count += len(kind.instances)
	}
	return count
}

// A frame of 8 by 1 by 8 cells of 500 mm round the surface vertex of the
// grid's mesh nearest the grid's centre, a quarter metre below it, every
// cell occupied.
cover_test_add_block :: proc(table: ^Frame_Table, grid: ^Field_Grid, mesh: Field_Mesh_Data) -> Frame_Id {
	centre := [3]f32{1, 1, 1} * FIELD_GRID_CELLS / 2
	nearest := mesh.positions[0]
	for position in mesh.positions {
		if linalg.length(position - centre) < linalg.length(nearest - centre) {
			nearest = position
		}
	}
	hit := sample_to_world_position(grid.origin, 1000) + World_Position{i64(math.round(nearest.x * POSITION_UNITS_PER_METRE)), i64(math.round(nearest.y * POSITION_UNITS_PER_METRE)), i64(math.round(nearest.z * POSITION_UNITS_PER_METRE))}
	up, _ := normalize_fixed(cast([3]i64)hit)
	axes := frame_axes(up, 0)
	origin := hit - World_Position(fixed_scale(up, metres_to_position_units(1) / 4) + fixed_scale(axes[FRAME_RIGHT], metres_to_position_units(2)) + fixed_scale(axes[FRAME_FORWARD], metres_to_position_units(2)))
	frame := add_frame(table, origin, axes, 500)
	for x in i32(0) ..< 8 {
		for z in i32(0) ..< 8 {
			occupy_frame_cell(table, frame, {x, 0, z}, {handle = 1})
		}
	}
	return frame
}

// The meadow node and cover_test_add_block's frame: no instance's base,
// middle or top lies in a cell, some stand within 2 m round the block,
// and without the frame some lie inside it.
@(test)
test_a_frame_clears_the_cover_under_its_cells :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	spots := COVER_TEST_SPOTS
	node := cover_test_surface_node(generation, cover_test_direction(spots[0].latitude, spots[0].longitude), 0, 0)
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	open, _, mesh := cover_test_grid_cover(generation, planet, grid)
	table: Frame_Table
	defer destroy_frame_table(&table)
	cover_test_add_block(&table, grid, mesh)
	frames := snapshot_cover_frames(&table, context.temp_allocator)
	testing.expect_value(t, len(frames), 1)
	testing.expect_value(t, len(frames[0].cells), 64)
	cleared, _ := cover_test_node_cover(generation, planet, node, frames[:])
	inside_before, around := 0, 0
	for kind in open.kinds {
		for instance in kind.instances {
			inside_before += cover_instance_cleared(frames[:], instance) ? 1 : 0
		}
	}
	for kind in cleared.kinds {
		for instance in kind.instances {
			testing.expect(t, !cover_instance_cleared(frames[:], instance), "an instance stands in a frame's cell")
			base := cover_instance_base(instance)
			local := frame_local_position(table.frames[0], World_Position{i64(math.round(f64(base.x) * POSITION_UNITS_PER_METRE)), i64(math.round(f64(base.y) * POSITION_UNITS_PER_METRE)), i64(math.round(f64(base.z) * POSITION_UNITS_PER_METRE))})
			metres := [3]f64{f64(local.x), f64(local.y), f64(local.z)} / POSITION_UNITS_PER_METRE
			if metres.x > -2 && metres.x < 6 && metres.z > -2 && metres.z < 6 {
				around += 1
			}
		}
	}
	testing.expectf(t, inside_before > 0, "%d instances lay in the block before it", inside_before)
	testing.expectf(t, around > 0, "%d instances stand round the block", around)
}

// Per kind the ranks rise and the rank counts rise to the count; at half
// the density every rank is under a half and 40 to 60 percent of the
// full row's stay; a limit of 100 keeps the 100 lowest ranks.
@(test) // slow
test_the_cover_thins_by_rank :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	spots := COVER_TEST_SPOTS
	node := cover_test_surface_node(generation, cover_test_direction(spots[0].latitude, spots[0].longitude), 0, 0)
	full, _ := cover_test_node_cover(generation, planet, node)
	half_row := COVER_TEST_ROW
	half_row.density_percent = 50
	half, _ := cover_test_node_cover(generation, planet, node, nil, half_row)
	limited_row := COVER_TEST_ROW
	limited_row.node_limit = 100
	limited, _ := cover_test_node_cover(generation, planet, node, nil, limited_row)
	grass := cover_test_kind(planet, "grass")
	testing.expectf(t, len(full.kinds[grass].instances) > 1000, "%d grass at the meadow", len(full.kinds[grass].instances))
	for kind, index in full.kinds {
		previous: f32 = 0
		for instance in kind.instances {
			testing.expect(t, cover_instance_rank(instance) >= previous, "the ranks rise")
			previous = cover_instance_rank(instance)
		}
		for step in 1 ..< COVER_RANK_STEPS {
			testing.expect(t, kind.rank_counts[step] >= kind.rank_counts[step - 1], "the rank counts rise")
		}
		testing.expect_value(t, int(kind.rank_counts[COVER_RANK_STEPS - 1]), len(kind.instances))
		for instance in half.kinds[index].instances {
			testing.expect(t, cover_instance_rank(instance) < 0.5, "half the density keeps the ranks under a half")
		}
		if len(kind.instances) >= 200 {
			share := f32(len(half.kinds[index].instances)) / f32(len(kind.instances))
			testing.expectf(t, share >= 0.4 && share <= 0.6, "half the density keeps %v of %s", share, planet.cover.kinds[index].id)
		}
		kept := limited.kinds[index].instances[:]
		testing.expect_value(t, len(kept), min(len(kind.instances), 100))
		for instance, position in kept {
			testing.expect_value(t, cover_instance_rank(instance), cover_instance_rank(kind.instances[position]))
		}
	}
}

// Two neighbouring meadow nodes: of their grass's positions within their
// node, under 1 percent coincide within 1 cm.
@(test)
test_neighbouring_nodes_scatter_differently :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	spots := COVER_TEST_SPOTS
	direction := cover_test_direction(spots[0].latitude, spots[0].longitude)
	first_node := cover_test_surface_node(generation, direction, 0, 0)
	second_node := cover_test_surface_node(generation, direction, 32, 0)
	testing.expect(t, first_node != second_node, "the nodes differ")
	grass := cover_test_kind(planet, "grass")
	first, _ := cover_test_node_cover(generation, planet, first_node)
	second, _ := cover_test_node_cover(generation, planet, second_node)
	cells := make(map[[3]i64][dynamic][3]f64, context.temp_allocator)
	second_origin := cover_test_node_origin(second_node, 1000)
	for instance in second.kinds[grass].instances {
		position := cover_test_vector(cover_instance_base(instance)) - second_origin
		cell := [3]i64{i64(math.floor(position.x * 100)), i64(math.floor(position.y * 100)), i64(math.floor(position.z * 100))}
		if cell not_in cells {
			cells[cell] = make([dynamic][3]f64, context.temp_allocator)
		}
		append(&cells[cell], position)
	}
	first_origin := cover_test_node_origin(first_node, 1000)
	coinciding := 0
	for instance in first.kinds[grass].instances {
		position := cover_test_vector(cover_instance_base(instance)) - first_origin
		cell := [3]i64{i64(math.floor(position.x * 100)), i64(math.floor(position.y * 100)), i64(math.floor(position.z * 100))}
		search: for x in i64(-1) ..= 1 {
			for y in i64(-1) ..= 1 {
				for z in i64(-1) ..= 1 {
					// Looked up first: ranging over a missing key's value
					// crashes Odin before dev-2026-11 (CI's nix job).
					others, found := cells[cell + {x, y, z}]
					if !found {
						continue
					}
					for other in others {
						if math.sqrt(cover_dot(other - position, other - position)) < 0.01 {
							coinciding += 1
							break search
						}
					}
				}
			}
		}
	}
	count := len(first.kinds[grass].instances)
	testing.expectf(t, count > 1000 && len(second.kinds[grass].instances) > 1000, "%d and %d grass", count, len(second.kinds[grass].instances))
	testing.expectf(t, coinciding * 100 < count, "%d of %d grass coincide", coinciding, count)
}

// A level 1 grid carries none, and neither does a cover turned off by the
// row's density, a planet without a climate or one without kinds.
@(test) // slow
test_only_the_finest_level_carries_cover :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	spots := COVER_TEST_SPOTS
	direction := cover_test_direction(spots[0].latitude, spots[0].longitude)
	node := cover_test_surface_node(generation, direction, 0, 0)
	coarse := Field_Node{1, {node.coordinate.x >> 1, node.coordinate.y >> 1, node.coordinate.z >> 1}}
	coarse_cover, area := cover_test_node_cover(generation, planet, coarse)
	testing.expect(t, area > 0, "the level 1 node holds the surface")
	testing.expect_value(t, cover_test_count(coarse_cover), 0)
	off_row := COVER_TEST_ROW
	off_row.density_percent = 0
	off, _ := cover_test_node_cover(generation, planet, node, nil, off_row)
	testing.expect_value(t, cover_test_count(off), 0)
	testing.expect(t, !make_field_cover_table(generation, planet, off_row).on, "a density of 0 turns the cover off")
	climateless := planet
	climateless.climate = {}
	climateless_cover, _ := cover_test_node_cover(make_planet_generation(DEFAULT_WORLD_SEED, climateless, 1000), climateless, node)
	testing.expect_value(t, cover_test_count(climateless_cover), 0)
	bare := planet
	bare.cover = {}
	bare_cover, _ := cover_test_node_cover(generation, bare, node)
	testing.expect_value(t, cover_test_count(bare_cover), 0)
}

// field.fs splits the topsoil at the steepness the cover's shares read.
@(test)
test_the_cover_reads_the_looks_steepness :: proc(t: ^testing.T) {
	fragment := #load("../data/shaders/field.fs", string)
	for line in ([?]string {
			fmt.tprintf("const float rock_start_steepness = %.3f;", GROUND_ROCK_START_STEEPNESS),
			fmt.tprintf("const float rock_full_steepness = %.3f;", GROUND_ROCK_FULL_STEEPNESS),
			fmt.tprintf("const float sand_start_steepness = %.3f;", GROUND_SAND_START_STEEPNESS),
			fmt.tprintf("const float sand_end_steepness = %.3f;", GROUND_SAND_END_STEEPNESS),
		}) {
		testing.expectf(t, strings.contains(fragment, line), "field.fs does not hold %s", line)
	}
}

// Work item 0335: the snow field.fs draws buries the kinds that do not
// grow on it.
@(test)
test_cover_snow_buries_by_the_kinds_snow :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	grass, boulders := cover_test_table_kind(planet, "grass"), cover_test_table_kind(planet, "boulders")
	middle: f32 = (COVER_SNOW_THIN_WEIGHT + COVER_SNOW_GONE_WEIGHT) / 2
	testing.expect(t, !cover_snow_buries(grass, COVER_SNOW_THIN_WEIGHT, 0), "the snow buries grass at the thin weight")
	testing.expect(t, cover_snow_buries(grass, COVER_SNOW_GONE_WEIGHT, f32(65535) / 65536), "grass stands at the gone weight")
	testing.expect(t, cover_snow_buries(grass, middle, 0.4), "grass stands half way with the unit 0.4")
	testing.expect(t, !cover_snow_buries(grass, middle, 0.6), "the snow buries grass half way with the unit 0.6")
	testing.expect(t, !cover_snow_buries(boulders, 1, 0), "the snow buries a boulder")
	half := grass
	half.surfaces[.Snow] = 0.5
	testing.expect(t, cover_snow_buries(half, COVER_SNOW_GONE_WEIGHT, 0.4), "a kind growing on half the snow stands at the gone weight with the unit 0.4")
	testing.expect(t, !cover_snow_buries(half, COVER_SNOW_GONE_WEIGHT, 0.6), "the snow buries a kind growing on half of it with the unit 0.6")
}

// A triangle at (0, 8000, 0) m, a metre a side, every corner with the
// normal, all topsoil, snow 128 and the natural share; its corners are
// the given vertices.
cover_test_hand_triangle :: proc(corners: ^[3]Cover_Vertex, normal: [3]f64, natural: u8) -> (triangle: Cover_Triangle) {
	offsets := [3][3]f64{{0, 0, 0}, {1, 0, 0}, {0, 0, 1}}
	for index in 0 ..< 3 {
		corners[index] = {position = [3]f64{0, 8000, 0} + offsets[index], normal = normal}
		triangle.corners[index] = &corners[index]
		triangle.surfaces[index].weights[field_material_slot(.Topsoil)] = 255
		triangle.surfaces[index].look.snow = 128
		triangle.surfaces[index].look.natural = natural
	}
	return triangle
}

// The triangle's point at the barycentric shares.
cover_test_triangle_point :: proc(triangle: Cover_Triangle, shares: [3]f64) -> (point: [3]f64) {
	for corner, index in triangle.corners {
		point += shares[index] * corner.position
	}
	return point
}

// cover_point_snow follows field.fs's snow terms and the inputs field.vs
// hands them.
@(test)
test_cover_point_snow_twins_field_fs :: proc(t: ^testing.T) {
	fragment := #load("../data/shaders/field.fs", string)
	for line in ([?]string {
			"vec3 normal = normalize(fragment_normal);",
			"float weight_sum = dot(fragment_weights, vec4(1.0)) + dot(fragment_ore_weights, vec3(1.0));",
			"vec4 weights = fragment_weights / max(weight_sum, smallest_weight_sum);",
			"float steepness = 1.0 - dot(normal, normalize(fragment_world_position));",
			"float topsoil = weights.x;",
			"float rock = topsoil * ground_look_on * smoothstep(rock_start_steepness, rock_full_steepness, steepness);",
			"float cover = (topsoil - rock) * ground_look_on * fragment_look.z;",
			"float snow = cover * fragment_look.x;",
		}) {
		testing.expectf(t, strings.contains(fragment, line), "field.fs does not hold %s", line)
	}
	vertex := #load("../data/shaders/field.vs", string)
	testing.expect(t, strings.contains(vertex, "fragment_look = unpack_bytes(vertexTexCoord2.y);"), "field.vs does not hand fragment_look the look's second bytes")
	corners: [3]Cover_Vertex
	centroid := [3]f64{1, 1, 1} / 3
	triangle := cover_test_hand_triangle(&corners, {0, 1, 0}, 255)
	snow := cover_point_snow(triangle, centroid, cover_test_triangle_point(triangle, centroid))
	testing.expectf(t, abs(f64(snow) - 128.0 / 255) < 1e-6, "the flat triangle's snow is %v", snow)
	sixty := math.PI / 3
	triangle = cover_test_hand_triangle(&corners, {math.sin(sixty), math.cos(sixty), 0}, 255)
	testing.expect_value(t, cover_point_snow(triangle, centroid, cover_test_triangle_point(triangle, centroid)), 0)
	triangle = cover_test_hand_triangle(&corners, {0, 1, 0}, 255)
	triangle.surfaces[0].weights = {}
	triangle.surfaces[0].weights[field_material_slot(.Stone)] = 255
	stone_corner := [3]f64{1, 0, 0}
	testing.expect_value(t, cover_point_snow(triangle, stone_corner, cover_test_triangle_point(triangle, stone_corner)), 0)
	between := [3]f64{0.5, 0.5, 0}
	snow = cover_point_snow(triangle, between, cover_test_triangle_point(triangle, between))
	testing.expectf(t, abs(f64(snow) - 64.0 / 255) < 1e-6, "half way off the stone corner the snow is %v", snow)
	triangle = cover_test_hand_triangle(&corners, {0, 1, 0}, 0)
	testing.expect_value(t, cover_point_snow(triangle, centroid, cover_test_triangle_point(triangle, centroid)), 0)
}

// field.fs's snow weight at the barycentric shares of a mesh triangle's
// corners (its indices), from the vertex arrays as field.vs unpacks them:
// the weights from the tangent and the ores' bytes, the snow and the
// natural share from the look's second bytes, the normal, and the up the
// world position (the node's origin plus the position) normalised.
cover_test_fragment_snow :: proc(mesh: Field_Mesh_Data, origin: [3]f64, indices: [3]int, shares: [3]f64) -> f64 {
	topsoil, total, natural, snow: f64
	normal, position: [3]f64
	for index, corner in indices {
		share := shares[corner]
		weights := mesh.weights[index]
		ores := unpack_test_bytes(mesh.lights[index][1])
		look := unpack_test_bytes(mesh.looks[index][1])
		total += share * f64(weights.x + weights.y + weights.z + weights.w + ores.x + ores.y + ores.z)
		topsoil += share * f64(weights.x)
		snow += share * f64(look.x)
		natural += share * f64(look.z)
		normal += share * cover_test_vector(mesh.normals[index])
		position += share * cover_test_vector(mesh.positions[index])
	}
	topsoil /= max(total, 0.0001)
	steepness := 1 - linalg.dot(linalg.normalize(normal), linalg.normalize(origin + position))
	rock := topsoil * math.smoothstep(f64(GROUND_ROCK_START_STEEPNESS), f64(GROUND_ROCK_FULL_STEEPNESS), steepness)
	return (topsoil - rock) * natural * snow
}

// Ahead and aside metres from the cold spot along its north and east
// tangents: four nodes across a snow line, field.fs's snow weight from 0
// to 1 across them at the shipped seed.
COVER_TEST_SNOW_LINE :: [4][2]i64{{-256, -672}, {-256, -640}, {-256, -608}, {-256, -576}}

// Nodes' cover against field.fs's snow: the instances found on no
// triangle; per band of the triangles' centroid weight (under
// COVER_SNOW_THIN_WEIGHT, under COVER_SNOW_GONE_WEIGHT, over) the grass
// standing on them and their area in square metres; the boulders standing
// at the gone weight or over; the most snow under an instance of a kind
// growing on none.
Cover_Test_Snow_Tally :: struct {
	missing:          int,
	grass:            [3]int,
	area:             [3]f64,
	boulders_on_snow: int,
	most_buried_snow: f64,
}

cover_test_snow_band :: proc(snow: f64) -> int {
	if snow < COVER_SNOW_THIN_WEIGHT {
		return 0
	}
	return snow < COVER_SNOW_GONE_WEIGHT ? 1 : 2
}

cover_test_triangle_indices :: proc(mesh: Field_Mesh_Data, triangle: int) -> [3]int {
	return {int(mesh.indices[3 * triangle]), int(mesh.indices[3 * triangle + 1]), int(mesh.indices[3 * triangle + 2])}
}

// The column's length in the instance's transform.
cover_test_column_length :: proc(instance: matrix[4, 4]f32, column: int) -> f64 {
	return math.sqrt(f64(instance[0, column] * instance[0, column] + instance[1, column] * instance[1, column] + instance[2, column] * instance[2, column]))
}

// The triangle the instance stands on, found as
// test_the_cover_lies_on_its_triangles finds it among the triangles whose
// centroid lies within 3 m of its base, and field.fs's snow weight at the
// hit; -1 when none holds it.
cover_test_instance_snow :: proc(mesh: Field_Mesh_Data, origin: [3]f64, centroids: [][3]f64, kind: Field_Cover_Kind, instance: matrix[4, 4]f32) -> (triangle: int, snow: f64) {
	base := cover_test_vector(cover_instance_base(instance)) - origin
	up := cover_test_vector({instance[0, 1], instance[1, 1], instance[2, 1]})
	height := cover_test_column_length(instance, 1)
	least := f64(kind.sink) * height
	most := least + 0.5 * max(cover_test_column_length(instance, 0), cover_test_column_length(instance, 2))
	for centroid, index in centroids {
		if cover_dot(centroid - base, centroid - base) > 9 {
			continue
		}
		corners := cover_test_triangle_indices(mesh, index)
		a, b, c := cover_test_vector(mesh.positions[corners[0]]), cover_test_vector(mesh.positions[corners[1]]), cover_test_vector(mesh.positions[corners[2]])
		distance, along, across, hit := cover_test_ray_barycentric(base, up / height, a, b, c)
		if hit && distance >= least - 0.005 && distance <= most + 0.005 {
			return index, cover_test_fragment_snow(mesh, origin, corners, {1 - along - across, along, across})
		}
	}
	return -1, 0
}

// The node's generated grid's cover added to the tally.
cover_test_tally_snow :: proc(generation: Planet_Generation, planet: Planet, node: Field_Node, tally: ^Cover_Test_Snow_Tally) {
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	data, _, mesh := cover_test_grid_cover(generation, planet, grid)
	origin := cover_test_node_origin(node, generation.spacing_millimetres)
	table := make_field_cover_table(generation, planet, COVER_TEST_ROW)
	triangle_count := len(mesh.indices) / 3
	centroids := make([][3]f64, triangle_count, context.temp_allocator)
	bands := make([]int, triangle_count, context.temp_allocator)
	for triangle in 0 ..< triangle_count {
		corners := cover_test_triangle_indices(mesh, triangle)
		a, b, c := cover_test_vector(mesh.positions[corners[0]]), cover_test_vector(mesh.positions[corners[1]]), cover_test_vector(mesh.positions[corners[2]])
		centroids[triangle] = (a + b + c) / 3
		bands[triangle] = cover_test_snow_band(cover_test_fragment_snow(mesh, origin, corners, [3]f64{1, 1, 1} / 3))
		tally.area[bands[triangle]] += linalg.length(cover_cross(b - a, c - a)) / 2
	}
	grass, boulders := cover_test_kind(planet, "grass"), cover_test_kind(planet, "boulders")
	for kind, kind_index in data.kinds {
		for instance in kind.instances {
			triangle, snow := cover_test_instance_snow(mesh, origin, centroids, table.kinds[kind_index], instance)
			if triangle < 0 {
				tally.missing += 1
				continue
			}
			if kind_index == grass {
				tally.grass[bands[triangle]] += 1
			}
			if kind_index == boulders && snow >= COVER_SNOW_GONE_WEIGHT {
				tally.boulders_on_snow += 1
			}
			if table.kinds[kind_index].surfaces[.Snow] == 0 {
				tally.most_buried_snow = max(tally.most_buried_snow, snow)
			}
		}
	}
}

// No plant, pebble or speck stands where field.fs draws snow at the cold
// spot's node and across a snow line, the grass thinning out over the
// snow's edge, and boulders stand on the snow.
@(test) // slow
test_snow_buries_the_plants :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	spots := COVER_TEST_SPOTS
	direction := cover_test_direction(spots[3].latitude, spots[3].longitude)
	cold, line: Cover_Test_Snow_Tally
	cover_test_tally_snow(generation, planet, cover_test_surface_node(generation, direction, 0, 0), &cold)
	snow_line := COVER_TEST_SNOW_LINE
	for place in snow_line {
		cover_test_tally_snow(generation, planet, cover_test_surface_node(generation, direction, place[0], place[1]), &line)
	}
	density: [3]f64
	for band in 0 ..< 3 {
		density[band] = f64(line.grass[band]) / max(line.area[band], 1)
	}
	log.infof("snow line: grass a square metre %.2f under the thin weight (%.0f m2), %.2f thinning (%.0f m2), %.2f over the gone weight (%.0f m2); cold spot: %d grass on %.0f m2; boulders on the snow %d; the most snow under a kind growing on none %.3f", density[0], line.area[0], density[1], line.area[1], density[2], line.area[2], cold.grass[0] + cold.grass[1] + cold.grass[2], cold.area[0] + cold.area[1] + cold.area[2], cold.boulders_on_snow + line.boulders_on_snow, max(cold.most_buried_snow, line.most_buried_snow))
	testing.expect_value(t, cold.missing + line.missing, 0)
	testing.expectf(t, max(cold.most_buried_snow, line.most_buried_snow) < COVER_SNOW_GONE_WEIGHT + 0.001, "a kind growing on no snow stands on snow of weight %v", max(cold.most_buried_snow, line.most_buried_snow))
	testing.expect_value(t, cold.grass[0] + cold.grass[1] + cold.grass[2], 0)
	testing.expectf(t, density[0] >= 2, "the snow line's bare ground holds %v grass a square metre", density[0])
	testing.expectf(t, density[1] > 0 && density[1] < density[0] / 2, "the snow line's thinning ground holds %v grass a square metre against %v on the bare", density[1], density[0])
	testing.expect(t, cold.boulders_on_snow + line.boulders_on_snow > 0, "no boulder stands on the snow")
}

// The cover's cost on the mesh job (0311), single threaded and not a
// benchmark; the suite leaves it out:
// ./build.sh test quick test_report_the_cover_cost -o:speed -define:COVER_COST=true
// or in ./build.sh nightly.
COVER_COST :: #config(COVER_COST, false)

when COVER_COST {
	@(test)
	test_report_the_cover_cost :: proc(t: ^testing.T) {
		planet := shipped_test_home_at(8000)
		spots := COVER_TEST_SPOTS
		for spacing in ([2]int{1000, 500}) {
			generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, spacing)
			for spot in spots {
				report_cover_cost(generation, planet, spot)
			}
		}
	}

	// Over the spot's node and its neighbours, the fastest of three
	// meshes of each grid without and with the cover, their means, and
	// the instances per kind and the most in a node.
	report_cover_cost :: proc(generation: Planet_Generation, planet: Planet, spot: Cover_Test_Spot) {
		direction := cover_test_direction(spot.latitude, spot.longitude)
		look := make_field_ground_look(generation, planet)
		table := make_field_cover_table(generation, planet, COVER_TEST_ROW)
		node_metres := i64(FIELD_GRID_CELLS) * i64(generation.spacing_millimetres) / MILLIMETRES_PER_METRE
		seen := make(map[Field_Node]struct{}, context.temp_allocator)
		without, with: time.Duration
		counts: [MAXIMUM_COVER_KINDS]int
		nodes, most := 0, 0
		for ahead in ([3]i64{-node_metres, 0, node_metres}) {
			for aside in ([3]i64{-node_metres, 0, node_metres}) {
				node := cover_test_surface_node(generation, direction, ahead, aside)
				if node in seen {
					continue
				}
				seen[node] = {}
				grid := new(Field_Grid, context.temp_allocator)
				generate_field_grid(generation, node, grid)
				if field_grid_is_uniform(grid) {
					continue
				}
				fastest := [2]time.Duration{max(time.Duration), max(time.Duration)}
				data: Field_Cover_Data
				for _ in 0 ..< 3 {
					begin := time.tick_now()
					mesh_field_grid(grid, planet.palette, generation.spacing_millimetres, EVERY_FIELD_FACE, context.temp_allocator, look, true)
					fastest[0] = min(fastest[0], time.tick_since(begin))
					begin = time.tick_now()
					mesh_field_grid(grid, planet.palette, generation.spacing_millimetres, EVERY_FIELD_FACE, context.temp_allocator, look, true, &data, table)
					fastest[1] = min(fastest[1], time.tick_since(begin))
				}
				without += fastest[0]
				with += fastest[1]
				nodes += 1
				node_count := 0
				for kind, index in data.kinds {
					counts[index] += len(kind.instances)
					node_count += len(kind.instances)
				}
				most = max(most, node_count)
			}
		}
		line := strings.builder_make(context.temp_allocator)
		for kind, index in planet.cover.kinds {
			fmt.sbprintf(&line, " %s %d", kind.id, counts[index])
		}
		milliseconds := proc(duration: time.Duration, count: int) -> f64 {
			return time.duration_milliseconds(duration) / f64(max(count, 1))
		}
		log.infof("cover cost at the %s, %d mm: %d nodes, a mesh %.2f ms without the cover and %.2f ms with it, at most %d instances a node; instances:%s", spot.name, generation.spacing_millimetres, nodes, milliseconds(without, nodes), milliseconds(with, nodes), most, strings.to_string(line))
	}
}
