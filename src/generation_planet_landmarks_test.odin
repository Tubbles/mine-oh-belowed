package game

import "core:slice"
import "core:strings"
import "core:testing"

// Work item 0323: the landmarks.

// The shipped landmarks as the design tuned them, on the landforms'
// design planet (design_landform_test_planet), so a later data retune
// leaves the tests.
design_landmark_test_planet :: proc(radius_metres: int) -> Planet {
	planet := design_landform_test_planet(radius_metres)
	planet.landmarks = Planet_Landmarks {
		gorge_mask_percent      = 8,
		mesa_mask_percent       = 16,
		mask_fade_percent       = 14,
		region_gorges_percent   = {0, 0, 0, 0, 40, 100, 100, 100, 100},
		region_mesas_percent    = {0, 0, 30, 100, 100, 70, 20, 0, 0},
		gorge_wavelength_metres = 700,
		gorge_meander_percent   = 18,
		gorge_width_permille    = 40,
		gorge_floor_percent     = 30,
		gorge_metres            = 26,
		dry_metres              = 1,
		mesa_wavelength_metres  = 640,
		mesa_rough_percent      = 35,
		mesa_threshold_percent  = 12,
		mesa_tier_percent       = 12,
		mesa_edge_permille      = 30,
		mesa_metres             = 13,
		site_spacing_metres     = 448,
		spire_percent           = 30,
		butte_percent           = 25,
		sinkhole_percent        = 15,
		spire_radius_metres     = {10, 18},
		spire_metres            = {28, 52},
		butte_radius_metres     = {20, 40},
		butte_metres            = {14, 28},
		butte_stretch_percent   = 220,
		sinkhole_radius_metres  = {12, 24},
		sinkhole_metres         = {9, 18},
		wobble_percent          = 30,
	}
	return planet
}

// Every placed site of the kind whose lattice cell lies in the box of the
// home plus and minus the reach, nearest the home first.
test_landmark_sites :: proc(generation: Planet_Generation, kind: Landmark_Kind, reach_metres: int, allocator := context.temp_allocator) -> [dynamic]Landmark_Site {
	spacing := metres_to_position_units(i64(generation.landmarks.site_spacing_metres))
	reach := metres_to_position_units(i64(reach_metres))
	home := generation.landform_home
	least, most: [3]i64
	for axis in 0 ..< 3 {
		least[axis] = floor_divide_i64(home[axis] - reach, spacing)
		most[axis] = floor_divide_i64(home[axis] + reach, spacing)
	}
	Placed :: struct {
		squared: i64,
		site:    Landmark_Site,
	}
	placed := make([dynamic]Placed, context.temp_allocator)
	for z in least.z ..= most.z {
		for y in least.y ..= most.y {
			for x in least.x ..= most.x {
				cell := [3]i64{x, y, z}
				site, candidate := landmark_site_candidate(generation, cell)
				if site.kind != kind {
					continue
				}
				if site = place_landmark_site(generation, cell, site, candidate); site.kind == kind {
					append(&placed, Placed{squared_chord(site.centre, home), site})
				}
			}
		}
	}
	slice.sort_by(placed[:], proc(first, second: Placed) -> bool {
		return first.squared < second.squared
	})
	sites := make([dynamic]Landmark_Site, 0, len(placed), allocator)
	for entry in placed {
		append(&sites, entry.site)
	}
	return sites
}

// The prototype's golden values (tmp/0323/proto, mode goldens without
// 0324's kinds): the home and the plain unchanged, a mesa, a sinkhole,
// spires, gorges, a butte and cells whose roll falls past the three kinds.
// The sites' values were re-pinned when the wobble came to vanish at the
// rim (0323's review): (80, 109) and (85, -103), near a rim, now read the
// ground without their site.
@(test)
test_landmark_relief_matches_the_design :: proc(t: ^testing.T) {
	Golden :: struct {
		latitude, longitude: int,
		relief:              i64,
	}
	generation := make_planet_generation(DEFAULT_WORLD_SEED, design_landmark_test_planet(8000), 1000)
	with := [?]Golden {
		{83, 132, 2697}, {81, 139, 113668},
		{85, 155, 26025}, {85, 156, 41810}, {84, 159, 13595},
		{82, 159, 102803},
		{80, 110, 146011}, {80, 109, 84286}, {80, 174, 227806},
		{76, 121, 146494}, {75, 135, 19593}, {77, 166, 191302},
		{85, -102, -153706}, {85, -103, -149101},
		{77, 144, 140031}, {86, 7, -3250},
	}
	for golden in with {
		testing.expectf(t, uncratered_relief(generation, test_degree_point(generation, golden.latitude, golden.longitude)) == golden.relief, "(%d, %d) with the landmarks", golden.latitude, golden.longitude)
	}
	landforms := make_planet_generation(DEFAULT_WORLD_SEED, design_landform_test_planet(8000), 1000)
	without := [?]Golden{{85, 155, -12553}, {82, 159, 154417}, {80, 110, 101192}, {76, 121, 199259}, {85, -102, -153740}, {77, 144, 140031}, {86, 7, -3250}}
	for golden in without {
		testing.expectf(t, uncratered_relief(landforms, test_degree_point(landforms, golden.latitude, golden.longitude)) == golden.relief, "(%d, %d) without the landmarks", golden.latitude, golden.longitude)
	}
	Radius_Golden :: struct {
		radius_metres:       int,
		latitude, longitude: int,
		without, with:       i64,
	}
	radii := [?]Radius_Golden{{4000, 60, -130, -78136, 28360}, {16000, 60, -148, -12931, 91978}, {16000, 60, 79, 148182, 90300}}
	for golden in radii {
		before := make_planet_generation(DEFAULT_WORLD_SEED, design_landform_test_planet(golden.radius_metres), 1000)
		after := make_planet_generation(DEFAULT_WORLD_SEED, design_landmark_test_planet(golden.radius_metres), 1000)
		testing.expect_value(t, uncratered_relief(before, test_degree_point(before, golden.latitude, golden.longitude)), golden.without)
		testing.expect_value(t, uncratered_relief(after, test_degree_point(after, golden.latitude, golden.longitude)), golden.with)
	}
}

// The bound is the landforms' and the relief stays inside it at every
// preset; a cut stops at the floor over the sea.
@(test) // slow
test_the_landmarks_keep_the_relief_bound :: proc(t: ^testing.T) {
	testing.expect_value(t, planet_relief_bounds(design_landmark_test_planet(8000)), planet_relief_bounds(design_landform_test_planet(8000)))
	for radius in ([3]int{4000, 8000, 16000}) {
		generation := make_planet_generation(DEFAULT_WORLD_SEED, design_landmark_test_planet(radius), 1000)
		landforms := make_planet_generation(DEFAULT_WORLD_SEED, design_landform_test_planet(radius), 1000)
		floor := max(generation.sea_radius - generation.radius + metres_to_position_units(1), generation.relief_lowest)
		for index in i64(0) ..< 20_000 {
			point := test_line_point(generation, index)
			relief := surface_relief(generation, point)
			testing.expectf(t, relief >= generation.relief_lowest && relief <= generation.relief_highest, "%d m, %d: the relief %d leaves the bound", radius, index, relief)
			if relief < surface_relief(landforms, point) {
				testing.expectf(t, relief >= floor, "%d m, %d: a cut to %d passes the floor %d", radius, index, relief, floor)
			}
		}
	}
}

// Within 80 m of the home the relief is the landforms' and no site
// reaches into the calm circle.
@(test)
test_the_landmarks_keep_the_home_calm :: proc(t: ^testing.T) {
	for radius in ([3]int{4000, 8000, 16000}) {
		planet := design_landmark_test_planet(radius)
		generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
		landforms := make_planet_generation(DEFAULT_WORLD_SEED, design_landform_test_planet(radius), 1000)
		home := planet_home_direction(planet.home)
		for index in i64(0) ..< 2000 {
			point := test_scattered_point(generation, home, index, 80)
			testing.expect_value(t, uncratered_relief(generation, point), uncratered_relief(landforms, point))
		}
		calm := metres_to_position_units(i64(planet.landforms.calm_metres))
		for kind in ([3]Landmark_Kind{.Spire, .Butte, .Sinkhole}) {
			for site in test_landmark_sites(generation, kind, 1500) {
				reach := calm + landmark_site_outer(site)
				testing.expectf(t, squared_chord(site.centre, generation.landform_home) >= reach * reach, "%d m: a %v reaches into the calm circle", radius, kind)
			}
		}
	}
}

// Within 3 km of the home stand at least 10 of each kind at every preset
// (measured 33, 18 and 14 at 4 km, 38, 12 and 18 at 8 km, 29, 21 and 14
// at 16 km).
@(test)
test_every_site_kind_stands_near_the_home :: proc(t: ^testing.T) {
	for radius in ([3]int{4000, 8000, 16000}) {
		generation := make_planet_generation(DEFAULT_WORLD_SEED, design_landmark_test_planet(radius), 1000)
		reach := metres_to_position_units(3000)
		for kind in ([3]Landmark_Kind{.Spire, .Butte, .Sinkhole}) {
			count := 0
			for site in test_landmark_sites(generation, kind, 3000) {
				count += squared_chord(site.centre, generation.landform_home) <= reach * reach ? 1 : 0
			}
			testing.expectf(t, count >= 10, "%d m: %d of %v within 3 km of the home", radius, count, kind)
		}
	}
}

// Just inside a site's reach, along 32 directions from every site within
// 1500 m of the home at 8 km, the site raises or cuts less than 1 mm: the
// wobble vanishes at the rim, so the relief meets the ground round it.
@(test)
test_a_site_meets_the_ground_at_its_rim :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, design_landmark_test_planet(8000), 1000)
	millimetre := metres_to_position_units(1) / 1000
	inside := 0
	for kind in ([3]Landmark_Kind{.Spire, .Butte, .Sinkhole}) {
		for site in test_landmark_sites(generation, kind, 1500) {
			up, _ := normalize_fixed(site.centre)
			forward := tangent_of(up, {UNIT_VECTOR_ONE, 0, 0})
			right := fixed_cross(forward, up)
			outer := landmark_site_outer(site)
			for index in 0 ..< 32 {
				angle := i32(index * ANGLE_UNITS_PER_TURN / 32)
				direction := fixed_scale(forward, fixed_cosine(angle)) + fixed_scale(right, fixed_sine(angle))
				offset := site.centre + fixed_scale(direction, outer - 8)
				point := project_onto_sphere(World_Position(offset), vector_length(offset), generation.radius)
				if squared_chord(point, site.centre) >= outer * outer {
					continue
				}
				inside += 1
				raise, cut := landmark_site_relief(generation, point)
				testing.expectf(t, raise <= millimetre && cut <= millimetre, "a %v at %v steps by %d and %d at its rim", kind, site.centre, raise, cut)
			}
		}
	}
	testing.expectf(t, inside > 500, "%d of the rim's points lie inside the reach", inside)
}

// At the bounds' extremes (a radius of 100 km, a spacing of 8192 m, spires
// of 1 m) the prefilter keeps every site: each centre reads its own site.
@(test)
test_the_prefilter_keeps_every_site :: proc(t: ^testing.T) {
	planet := design_landmark_test_planet(100_000)
	planet.landmarks.site_spacing_metres = 8192
	planet.landmarks.spire_radius_metres = {1, 1}
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	sites := test_landmark_sites(generation, .Spire, 80_000)
	testing.expect(t, len(sites) > 20, "the box holds spires")
	for site in sites {
		found := landmark_site_at(generation, site.centre)
		testing.expectf(t, found.kind == .Spire && found.centre == site.centre, "the spire at %v reads %v", site.centre, found.kind)
	}
}

@(test)
test_landmarks_problems :: proc(t: ^testing.T) {
	testing.expect_value(t, landmarks_problem({}, {}), "")
	design := design_landmark_test_planet(8000)
	testing.expect_value(t, planet_problem(design), "")
	testing.expect_value(t, landmark_widest_site_metres(design.landmarks), 88)
	without_landforms := design
	without_landforms.landforms = {}
	testing.expect_value(t, planet_problem(without_landforms), "landmarks need landforms")
	cases := [?]struct {
		change:   proc(landmarks: ^Planet_Landmarks),
		expected: string,
	} {
		{proc(landmarks: ^Planet_Landmarks) {landmarks.mask_fade_percent = 0}, "landmarks.mask_fade_percent 0 is outside 1 to 100"},
		{proc(landmarks: ^Planet_Landmarks) {landmarks.region_gorges_percent[4] = 101}, "landmarks.region_gorges_percent[4] 101 is outside 0 to 100"},
		{proc(landmarks: ^Planet_Landmarks) {landmarks.gorge_floor_percent = 100}, "landmarks.gorge_floor_percent 100 is outside 0 to 99"},
		{proc(landmarks: ^Planet_Landmarks) {landmarks.mesa_edge_permille = 0}, "landmarks.mesa_edge_permille 0 is outside 1 to 1000"},
		{proc(landmarks: ^Planet_Landmarks) {landmarks.spire_percent = 61}, "landmarks' site shares add up to 101, more than 100"},
		{proc(landmarks: ^Planet_Landmarks) {landmarks.butte_metres = {28, 14}}, "landmarks.butte_metres [28, 14] runs backwards"},
		{proc(landmarks: ^Planet_Landmarks) {landmarks.butte_stretch_percent = 401}, "landmarks.butte_stretch_percent 401 is outside 100 to 400"},
		{proc(landmarks: ^Planet_Landmarks) {landmarks.site_spacing_metres = 177}, "landmarks.site_spacing_metres 177 is outside 178 to 8192"},
		{proc(landmarks: ^Planet_Landmarks) {landmarks.wobble_percent = 91}, "landmarks.wobble_percent 91 is outside 0 to 90"},
	}
	for entry in cases {
		landmarks := design.landmarks
		entry.change(&landmarks)
		testing.expect_value(t, landmarks_problem(landmarks, design.landforms), entry.expected)
		changed := design
		changed.landmarks = landmarks
		testing.expect(t, strings.contains(planet_problem(changed), entry.expected), entry.expected)
	}
	// A kind's keys are checked only while it is on.
	off := design.landmarks
	off.spire_percent = 0
	off.spire_radius_metres = {0, 0}
	testing.expect_value(t, landmarks_problem(off, design.landforms), "")
	shipped := string(#load("../data/planets.sjson"))
	missing, _ := strings.replace(shipped, "gorge_metres = 26", "", 1, context.temp_allocator)
	expect_planets_problem(t, missing, "planets[0].landmarks is missing gorge_metres")
}
