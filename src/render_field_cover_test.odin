package game

import "core:math"
import "core:testing"
import "generation_seed"

// Work item 0311: the ground cover's draw without the GPU.

// Work item 0349: every vertex of every shape, leaned as cover.vs leans a
// foliage part at the four extremes of its lean and drawn at full size,
// lies in its instance's box, for foliage and stones from the smallest to
// the largest, upright and tilted, on flat and sloped ground; the reach
// is foliage's half width plus cover.vs's lean.
@(test)
test_the_cover_box_holds_every_leaned_shape_vertex :: proc(t: ^testing.T) {
	part_lean, found := shader_float_constant(#load("../data/shaders/cover.vs", string), "part_lean")
	testing.expect(t, found && part_lean == 0.25, "cover.vs holds const float part_lean = 0.25;")
	testing.expect_value(t, f32(COVER_SHAPE_REACH), 0.5 + part_lean)
	cases := [?]struct {
		shape: Cover_Shape,
		parts: int,
	}{{.Blades, 9}, {.Flower, 3}, {.Fern, 7}, {.Pebble, 0}, {.Crystal, 0}}
	point := [3]f64{5000, 6000, 1000}
	up := cover_normalized(point, {0, 1, 0})
	aside, _ := cover_tangents(up, 0)
	tilt := 40 * math.RAD_PER_DEG
	normals := [2][3]f64{up, up * math.cos(tilt) + aside * math.sin(tilt)}
	leans := [4][2]f32{{-1, -1}, {-1, 1}, {1, -1}, {1, 1}}
	for entry in cases {
		foliage := cover_shape_is_foliage(entry.shape)
		kind := Field_Cover_Kind{width = {0.5, 4}, height = {0.3, 4}, foliage = foliage}
		outside := 0
		for seed_index in 0 ..< 3 {
			vertices := cover_shape_vertices(entry.shape, entry.parts, generation_seed.hash_combine(COVER_SHAPE_SEED, u64(seed_index)), context.temp_allocator)
			for normal in normals {
				for slope_tangent in ([2]f32{0, 0.8}) {
					for hash_set in 0 ..< 16 {
						hashes: [4]u64
						for &hash, slot in hashes {
							hash = generation_seed.hash_combine(0x0349, u64(4 * hash_set + slot))
						}
						instance := cover_instance(kind, point, up, normal, slope_tangent, {}, {}, hashes)
						minimum, maximum := cover_instance_box(instance)
						base := cover_instance_base(instance)
						right := [3]f32{instance[0, 0], instance[1, 0], instance[2, 0]}
						instance_up := [3]f32{instance[0, 1], instance[1, 1], instance[2, 1]}
						forward := [3]f32{instance[0, 2], instance[1, 2], instance[2, 2]}
						for vertex in vertices {
							for lean in leans {
								local := vertex.position
								if foliage {
									local.x += lean.x * part_lean * local.y
									local.z += lean.y * part_lean * local.y
								}
								world := base + right * local.x + instance_up * local.y + forward * local.z
								for axis in 0 ..< 3 {
									outside += world[axis] < minimum[axis] - 1e-3 || world[axis] > maximum[axis] + 1e-3 ? 1 : 0
								}
							}
						}
					}
				}
			}
		}
		testing.expectf(t, outside == 0, "%v: %d coordinates lie outside their instance's box", entry.shape, outside)
	}
}

// Every shape at its shipped parts: its vertices in the unit box (the
// stones within 0.6 sideways for their jitter), unit normals, a part's
// vertices times the parts for foliage, and every closed stone face
// turned outward.
@(test)
test_cover_shapes_fit_the_unit_box :: proc(t: ^testing.T) {
	cases := [?]struct {
		shape: Cover_Shape,
		parts: int,
	}{{.Blades, 9}, {.Flower, 3}, {.Fern, 7}, {.Pebble, 0}, {.Crystal, 0}}
	for entry in cases {
		for index in 0 ..< 3 {
			vertices := cover_shape_vertices(entry.shape, entry.parts, generation_seed.hash_combine(COVER_SHAPE_SEED, u64(index)), context.temp_allocator)
			testing.expectf(t, len(vertices) > 0 && len(vertices) % 3 == 0, "%v has %d vertices", entry.shape, len(vertices))
			side: f32 = cover_shape_is_foliage(entry.shape) ? 0.5 : 0.6
			if cover_shape_is_foliage(entry.shape) {
				testing.expect_value(t, len(vertices), entry.parts * cover_part_vertices(entry.shape))
			} else {
				testing.expect_value(t, cover_part_vertices(entry.shape), 0)
			}
			centre: [3]f32
			for vertex in vertices {
				centre += vertex.position / f32(len(vertices))
			}
			for vertex in vertices {
				position := vertex.position
				testing.expectf(t, abs(position.x) <= side + 1e-5 && abs(position.z) <= side + 1e-5 && position.y >= -1e-5 && position.y <= 1 + 1e-5, "%v has a vertex at %v", entry.shape, position)
				length := math.sqrt(vertex.normal.x * vertex.normal.x + vertex.normal.y * vertex.normal.y + vertex.normal.z * vertex.normal.z)
				testing.expectf(t, abs(length - 1) < 1e-4, "%v has a normal of length %v", entry.shape, length)
			}
			if !cover_shape_is_foliage(entry.shape) {
				for first := 0; first < len(vertices); first += 3 {
					face := (vertices[first].position + vertices[first + 1].position + vertices[first + 2].position) / 3 - centre
					normal := vertices[first].normal
					testing.expectf(t, face.x * normal.x + face.y * normal.y + face.z * normal.z > 0, "%v has a face turned inward", entry.shape)
				}
			}
		}
	}
	// A flower's stem keeps its own green, its head takes the instance's.
	flower := cover_shape_vertices(.Flower, 1, COVER_SHAPE_SEED, context.temp_allocator)
	testing.expect_value(t, flower[0].color, [4]u8{80, 112, 56, 0})
	testing.expect_value(t, flower[3].color.a, 255)
}

// None at or past the far distance, all within the near, the prefix of
// the rank step between, never more than the count.
@(test)
test_the_cover_draw_count_follows_the_distance :: proc(t: ^testing.T) {
	draw := Field_Cover_Node_Draw {
		count = 1600,
	}
	for step in 0 ..< COVER_RANK_STEPS {
		draw.rank_counts[step] = i32(100 * (step + 1))
	}
	testing.expect_value(t, cover_draw_count(draw, 10, 40, 40), 0)
	testing.expect_value(t, cover_draw_count(draw, 10, 40, 50), 0)
	testing.expect_value(t, cover_draw_count(draw, 10, 40, 10), 1600)
	testing.expect_value(t, cover_draw_count(draw, 10, 40, 0), 1600)
	// Halfway: ranks under a half, the eighth step.
	testing.expect_value(t, cover_draw_count(draw, 10, 40, 25), 800)
	// Just inside the far distance: the first step.
	testing.expect_value(t, cover_draw_count(draw, 10, 40, 39.9), 100)
	// A near at the far draws all inside it.
	testing.expect_value(t, cover_draw_count(draw, 40, 40, 39), 1600)
	// Fewer drawn as the distance grows.
	previous := draw.count
	for distance: f32 = 10; distance < 40; distance += 0.5 {
		count := cover_draw_count(draw, 10, 40, distance)
		testing.expectf(t, count <= previous, "%d at %v m after %d", count, distance, previous)
		previous = count
	}
}

// The reach is the row's share of the kind's, ending 8 m inside the first
// level: the 56 m boulders at 150 percent reach 56 m with a 64 m first
// level, 2 m with a 10 m one; the near never passes the far.
@(test)
test_the_cover_reach_stays_inside_the_first_level :: proc(t: ^testing.T) {
	boulders := Planet_Cover_Kind {
		near_metres = 30,
		far_metres  = 56,
	}
	row := Field_Cover_Row {
		distance_percent = 150,
		density_percent  = 100,
		node_limit       = 8192,
	}
	near, far := cover_reach(boulders, row, 64)
	testing.expect_value(t, far, 56)
	testing.expect_value(t, near, 45)
	near, far = cover_reach(boulders, row, 10)
	testing.expect_value(t, far, 2)
	testing.expect_value(t, near, 2)
	row.distance_percent = 60
	near, far = cover_reach(boulders, row, 64)
	testing.expect(t, abs(far - 33.6) < 1e-4 && abs(near - 18) < 1e-4, "the phone's row shortens both")
	_, far = cover_reach(boulders, row, 4)
	testing.expect_value(t, far, 0)
}
