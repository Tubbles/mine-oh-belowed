package game

import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:testing"

// The debris of the hit (work item 0272), pure: the landings, the pod's
// reach, the flights' bound and the patter.

ARRIVAL_DEBRIS_TEST_SPACING_MILLIMETRES :: 500

// The planet's generation for the seed with the pod placed at its home
// as a new world places it, rested at tilt; the debris' site from it.
debris_test_site :: proc(entities: ^Entities, machines: Machine_Registry, planet: Planet, config: Game_Config, seed, tilt: int) -> (site: Arrival_Debris_Site, frame: Frame, pod: Entity_Common) {
	generation := make_planet_generation(u64(seed), planet, ARRIVAL_DEBRIS_TEST_SPACING_MILLIMETRES)
	surface, heading := field_home_site(generation, planet)
	_, placed := place_pod(entities, machines, surface, heading, ARRIVAL_DEBRIS_TEST_SPACING_MILLIMETRES)
	assert(placed)
	pod, frame, _ = find_pod(entities, machines)
	machine := machines.machines[pod.machine]
	origin, axes := pod_rest_pose(frame, pod, machine, tilt)
	set_frame_pose(&entities.frames, frame.id, origin, axes)
	frame, _ = find_frame(&entities.frames, frame.id)
	found: bool
	site, found = arrival_debris_site(generation, config, world_position_to_metres(pod_base_centre(frame, pod)), arrival_pod_reach_metres(machine, frame))
	assert(found)
	return
}

// The distance from the home on the tangent plane that the point's
// radial passes through: the landing's intended distance, whatever the
// relief raised or lowered it along the radial.
debris_tangent_distance :: proc(site: Arrival_Debris_Site, point: [3]f32) -> f32 {
	direction := linalg.normalize(point)
	return linalg.length(site.home) * arrival_tangent_distance(direction, site.up) / linalg.dot(direction, site.up)
}

debris_metres_to_position :: proc(point: [3]f32) -> World_Position {
	return World_Position{i64(math.round(f64(point.x) * POSITION_UNITS_PER_METRE)), i64(math.round(f64(point.y) * POSITION_UNITS_PER_METRE)), i64(math.round(f64(point.z) * POSITION_UNITS_PER_METRE))}
}

// Seeds 1 to 16 on the shipped planet: every landing lies between the
// rim and five crater radii from the home, at least half within one
// radius of the rim; the arc ends on its landing and the piece rests
// there sunk a quarter of its edge; the inner half reaches farther than
// the outer half.
@(test)
test_every_clod_lands_within_five_radii_and_half_near_the_rim :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	machines := make_test_machines()
	planet := default_planet(shipped_test_planets())
	for seed in 1 ..= 16 {
		entities: Entities
		defer destroy_entities(&entities)
		site, _, _ := debris_test_site(&entities, machines, planet, config, seed, config.arrival_rest_tilt_degrees)
		radius := site.radius_metres
		near := 0
		inner_reach, outer_reach: f32
		inner_count, outer_count := 0, 0
		for index in 0 ..< site.pieces {
			piece := arrival_debris_piece(site, index, u64(seed))
			distance := debris_tangent_distance(site, piece.landing)
			testing.expectf(t, distance <= 5 * radius + 0.001, "seed %d piece %d lands %v m out, beyond five radii", seed, index, distance)
			testing.expectf(t, distance >= radius - 0.001, "seed %d piece %d lands %v m out, inside the rim", seed, index, distance)
			if distance <= 2 * radius {
				near += 1
			}
			end := arrival_debris_flight_point(piece, piece.flight_seconds)
			testing.expectf(t, linalg.length(end - (piece.landing + site.up * piece.edge_metres / 2)) < 0.001, "seed %d piece %d ends its arc %v from its landing", seed, index, end - (piece.landing + site.up * piece.edge_metres / 2))
			rest, _, edge, visible := arrival_debris_pose(piece, piece.launch_seconds + piece.flight_seconds + 0.01)
			testing.expect(t, visible)
			testing.expectf(t, linalg.length(rest - (piece.landing + site.up * edge / 4)) < 0.001, "seed %d piece %d rests %v from its landing sunk a quarter", seed, index, rest - (piece.landing + site.up * edge / 4))
			if piece.launch_seconds < ARRIVAL_DEBRIS_LAUNCH_SPREAD_SECONDS / 2 {
				inner_reach += piece.reach_metres
				inner_count += 1
			} else {
				outer_reach += piece.reach_metres
				outer_count += 1
			}
		}
		testing.expectf(t, 2 * near >= site.pieces, "seed %d: %d of %d pieces land within a radius of the rim", seed, near, site.pieces)
		testing.expectf(t, inner_count > 0 && outer_count > 0 && inner_reach / f32(inner_count) > outer_reach / f32(outer_count), "seed %d: the inner half does not reach farther", seed)
	}
}

// Seeds 1 to 16, crater radii 4, 12 and 18, the pod rested at 15 and 25
// degrees: no piece's centre lies in the pod's cells grown by one cell,
// at any tenth of a second of its arc nor at rest.
@(test)
test_no_clod_rests_on_the_pod :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	machines := make_test_machines()
	planet := default_planet(shipped_test_planets())
	// The smallest crater has no rim: a rim of 1 m over its 2 m of bowl
	// is steeper than crater_problem allows.
	craters := [3]Planet_Crater{{radius_metres = 4, depth_metres = 1, floor_radius_metres = 2, rim_metres = 0}, {radius_metres = 12, depth_metres = 3, floor_radius_metres = 2, rim_metres = 1}, {radius_metres = 18, depth_metres = 3, floor_radius_metres = 2, rim_metres = 1}}
	for crater in craters {
		testing.expect_value(t, crater_problem(crater), "")
		planet.crater = crater
		for tilt in ([2]int{15, 25}) {
			for seed in 1 ..= 16 {
				entities: Entities
				defer destroy_entities(&entities)
				site, frame, pod := debris_test_site(&entities, machines, planet, config, seed, tilt)
				for index in 0 ..< site.pieces {
					piece := arrival_debris_piece(site, index, u64(seed))
					steps := int(piece.flight_seconds / 0.1) + 1
					for step in 0 ..= steps + 1 {
						seconds := piece.launch_seconds + min(f32(step) * 0.1, piece.flight_seconds + 0.05)
						centre, _, _, visible := arrival_debris_pose(piece, seconds)
						testing.expect(t, visible)
						cell := world_to_frame_cell(frame, debris_metres_to_position(centre))
						inside := true
						for axis in 0 ..< 3 {
							inside = inside && cell[axis] >= pod.origin[axis] - 1 && cell[axis] <= pod.origin[axis] + pod.size[axis]
						}
						testing.expectf(t, !inside, "crater %d tilt %d seed %d: piece %d at %v s lies in the pod's cell %v", crater.radius_metres, tilt, seed, index, seconds, cell)
					}
				}
			}
		}
	}
}

// The deepest bowl and the widest crater at 30, 45 and 60 degrees: every
// launch plus flight stays below ARRIVAL_DEBRIS_FLIGHT_SECONDS, and every
// piece is hidden once the Settled phase ends.
@(test)
test_the_clods_fly_within_their_bound :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	machines := make_test_machines()
	planet := default_planet(shipped_test_planets())
	// The deepest bowl, and the widest crater (reach 24, landings out to
	// 120 m).
	craters := [2]Planet_Crater{{radius_metres = 18, depth_metres = 8, floor_radius_metres = 2, rim_metres = 1}, {radius_metres = 24, depth_metres = 3, floor_radius_metres = 4, rim_metres = 0}}
	for crater in craters {
		testing.expect_value(t, crater_problem(crater), "")
		planet.crater = crater
		for angle in ([3]int{30, 45, 60}) {
			config.arrival_debris_angle_degrees = angle
			for seed in 1 ..= 4 {
				entities: Entities
				defer destroy_entities(&entities)
				site, _, _ := debris_test_site(&entities, machines, planet, config, seed, config.arrival_rest_tilt_degrees)
				for index in 0 ..< site.pieces {
					piece := arrival_debris_piece(site, index, u64(seed))
					landing := piece.launch_seconds + piece.flight_seconds
					testing.expectf(t, landing < ARRIVAL_DEBRIS_FLIGHT_SECONDS, "crater %d angle %d seed %d piece %d lands at %v s", crater.radius_metres, angle, seed, index, landing)
					_, _, _, visible := arrival_debris_pose(piece, arrival_settled_seconds(config))
					testing.expectf(t, !visible, "crater %d angle %d seed %d piece %d shows past the Settled phase", crater.radius_metres, angle, seed, index)
				}
			}
		}
	}
}

// Pieces 0: the site is still found (the dust and the bang stay), no
// piece is drawn and none sounds, and the dust's puffs stand on the
// ground along the rim.
@(test)
test_no_pieces_keep_the_dust :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	config.arrival_debris_pieces = 0
	testing.expect_value(t, arrival_problem(config), "")
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	site, _, _ := debris_test_site(&entities, machines, default_planet(shipped_test_planets()), config, 1, config.arrival_rest_tilt_degrees)
	testing.expect_value(t, site.pieces, 0)
	testing.expect_value(t, min(site.pieces, MAXIMUM_ARRIVAL_DEBRIS_PIECES), 0)
	for index in 0 ..< ARRIVAL_DUST_PUFFS {
		azimuth, base, _, _, _, alpha := arrival_dust_puff(index, 0.5, 1, site.radius_metres)
		ground := arrival_debris_ground(site, azimuth, base)
		testing.expectf(t, abs(debris_tangent_distance(site, ground) - base) < 0.01, "puff %d stands %v m out, not at its base %v", index, debris_tangent_distance(site, ground), base)
		testing.expect(t, alpha > 0)
	}
}

// Seed 1: the sounding pieces land over at least 2 s, and the gaps
// between their landings vary (their coefficient of variation above 0.5),
// so the patter keeps no period.
@(test)
test_the_patter_has_no_period :: proc(t: ^testing.T) {
	config := shipped_arrival_config()
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	site, _, _ := debris_test_site(&entities, machines, default_planet(shipped_test_planets()), config, 1, config.arrival_rest_tilt_degrees)
	landings := make([dynamic]f32, context.temp_allocator)
	for index in 0 ..< site.pieces {
		_, _, _, landing, sounds := arrival_patter(site, index, 1)
		if sounds {
			append(&landings, landing)
		}
	}
	slice.sort(landings[:])
	testing.expect(t, len(landings) > 2)
	testing.expectf(t, landings[len(landings) - 1] - landings[0] >= 2, "the patter spans %v s", landings[len(landings) - 1] - landings[0])
	sum, squares: f32
	for index in 1 ..< len(landings) {
		gap := landings[index] - landings[index - 1]
		sum += gap
		squares += gap * gap
	}
	count := f32(len(landings) - 1)
	mean := sum / count
	deviation := math.sqrt(max(squares / count - mean * mean, 0))
	testing.expectf(t, deviation / mean > 0.5, "the gaps' coefficient of variation is %v", deviation / mean)
}
