package game

import "generation_seed"

// The landmarks of a planet (work item 0323, doc/architecture.md, World
// generation): gorges, mesas with their cliff bands, and sites (spires,
// buttes and sinkholes, and 0324's arches, grottos and mushroom rocks,
// carved under their raise), the last term of uncratered_relief, after
// Minecraft's canyon carver and its badlands. The gorges and the mesas lie
// in patches of the landforms' first warp noise (Landform_Reading.mask),
// so they cost no noise outside them and never overlap; the sites lie on
// a jittered lattice, one per cube at most, each disc inside its cube, so
// a point reads one cube. Every term scales with home_wildness or keeps
// clear of the calm circle. Raises clamp at the bound's highest and cuts
// stop at a floor over the sea, so the relief stays within the planet's
// bound. Integers and fixed point only, a pure function of the point, as
// the rest of the relief. Off at the zero Planet_Landmarks.
//
// The carve (0324), after Dey, Doig and Gatzidis's procedural arches
// (SIGGRAPH 2017): a carving site's column holds a signed distance over
// its ground (landmark_carve_distance), negative in the carved air, which
// the sample takes with the height map's depth (column_depth,
// generation_planet.odin). Two gradient noises of the site's scale, read
// once per column, weather the raise, the outline and every semi axis of
// the carve, so no two sites and no two sides of one site match. Each
// kind's carved air in a column is one span from the ground up, which
// the roof test (column_roofed) relies on.

// The bits of the site hash that jitter each axis.
SITE_JITTER_BITS :: 21
// How far a patch's weak edge raises the mesas' threshold, percent of
// the noise's range, so the patch ends in smaller mesas, never lower ones.
MESA_SHRINK_PERCENT :: 40

// An arch's stretch along its axis: a fin.
ARCH_LEAST_STRETCH_PERCENT :: 260
ARCH_MOST_STRETCH_PERCENT :: 340
// The carve's sizes, per mille: the arch's opening's half width of the
// fin's half length and its height of the site's height; the grotto's
// tunnel's half width of the radius and its height of that half width,
// its chamber's radius of the radius and its height of the site's; the
// mushroom rock's stem of the radius and its cap's thickness at its rim
// of the height.
ARCH_OPENING_WIDTH_PERMILLE :: 360
ARCH_OPENING_HEIGHT_PERMILLE :: 620
GROTTO_TUNNEL_PERMILLE :: 120
GROTTO_TUNNEL_HEIGHT_PERMILLE :: 1300
GROTTO_CHAMBER_PERMILLE :: 420
GROTTO_CHAMBER_HEIGHT_PERMILLE :: 560
MUSHROOM_STEM_PERMILLE :: 450
MUSHROOM_CAP_PERMILLE :: 220
// The weathering. The relief noise moves a carving site's raise and its
// outline by these shares, at a wavelength of its share of the radius
// (at least the least); the shape noise, at its own wavelength, moves
// the carve's semi axes.
CARVE_RELIEF_ROUGH_PERCENT :: 18
CARVE_OUTLINE_ROUGH_PERCENT :: 12
CARVE_RELIEF_WAVE_PERCENT :: 50
CARVE_RELIEF_LEAST_WAVE_METRES :: 4
CARVE_SHAPE_WAVE_PERCENT :: 35
CARVE_SHAPE_LEAST_WAVE_METRES :: 2
// A grotto's knoll falls steeply on its mouth's side (u grows by up to
// this share there) and its raise is moved by the shape noise too.
GROTTO_FACE_PERMILLE :: 600
GROTTO_KNOLL_ROUGH_PERCENT :: 15
// The arch's opening: its semi axes moved by the shape noise, its centre
// along the fin by the relief noise (of its half width), narrowing
// towards its crown.
ARCH_OPENING_ROUGH_PERCENT :: 22
ARCH_SKEW_PERCENT :: 18
ARCH_TAPER_PERMILLE :: 300
// The grotto's tunnel and chamber moved by the shape noise, the tunnel
// meandering by the relief noise (of its half width).
GROTTO_ROUGH_PERCENT :: 25
GROTTO_MEANDER_PERMILLE :: 700
// The mushroom rock's stem moved by the shape noise and narrower at its
// foot; its cap thicker towards the stem and its underside moved by the
// shape noise. A cap thinner than MUSHROOM_LEAST_CAP (position units,
// half a metre) or a gap under it under MUSHROOM_CLEARANCE_METRES is
// carved whole: the ragged rim.
MUSHROOM_STEM_ROUGH_PERCENT :: 20
MUSHROOM_FOOT_PERMILLE :: 350
MUSHROOM_THICKEN_PERCENT :: 80
MUSHROOM_UNDER_ROUGH_PERCENT :: 25
MUSHROOM_LEAST_CAP :: 2048
MUSHROOM_CLEARANCE_METRES :: 1

Landmark_Kind :: enum u8 {
	None,
	Spire,
	Butte,
	Sinkhole,
	Arch,
	Grotto,
	Mushroom,
}

// The kinds carved under their raise (0324).
CARVING_KINDS :: bit_set[Landmark_Kind]{.Arch, .Grotto, .Mushroom}

// A site, lengths in position units: its centre on the sphere, its cell's
// hash, its radius, its height (a sinkhole's depth) and its stretch along
// its axis (landmark_site_axis).
Landmark_Site :: struct {
	kind:                            Landmark_Kind,
	centre:                          [3]i64,
	hash:                            u64,
	radius, height, stretch_percent: i64,
}

// A kind's shape across its stretched radius, per mille of it: the cap
// out to cap, the wall from there to wall_end falling to talus per mille
// of the height, the talus falling with the square to none at the radius.
// The cap's top falls by crown per mille of the height from the centre
// to the cap's edge, with the square of the way (0324; 0 is flat).
Landmark_Profile :: struct {
	cap, wall_end, talus, crown: i64,
}

LANDMARK_PROFILES :: [Landmark_Kind]Landmark_Profile {
	.None     = {},
	.Spire    = {80, 450, 180, 0},
	.Butte    = {520, 640, 220, 0},
	.Sinkhole = {300, 700, 80, 0},
	.Arch     = {400, 720, 150, 250},
	.Grotto   = {420, 900, 50, 150},
	.Mushroom = {650, 780, 120, 200},
}

// A carving site's column (0324): the site (kind None outside every
// carving site), the column's ground (the relief before the site, with
// the mesas and without a gorge), the site's raise there, the weathered
// u, the offsets along and across the site's axis and the column's two
// noises. Lengths in position units.
Landmark_Carve :: struct {
	site:                      Landmark_Site,
	ground, raise, u:          i64,
	along, across:             i64,
	relief_noise, shape_noise: i64,
}

// The relief with the landmarks: the gorges cut, the mesas and the sites
// raise or cut, each where its patch, its region share and the wildness
// leave it any strength. The mask comes first, so a patch's ramp of 0
// skips its curve and its noise. Raises clamp at the bound's highest and
// cuts stop at the floor, dry_metres over the sea (the bound's lowest at
// least), so the relief stays within the planet's bound. The carve of a
// carving site's column comes with its ground, the relief with the mesas
// clamped as the result.
landmark_relief :: proc(generation: Planet_Generation, point: [3]i64, relief: i64, reading: Landform_Reading) -> (result: i64, carve: Landmark_Carve) {
	landmarks := generation.landmarks
	if landmarks.site_spacing_metres == 0 || reading.wildness == 0 {
		return relief, {}
	}
	floor := max(generation.sea_radius - generation.radius + metres_to_position_units(i64(landmarks.dry_metres)), generation.relief_lowest)
	fade := i64(landmarks.mask_fade_percent) * NOISE_ONE / 100
	raise, gorge: i64 = 0, 0
	if landmarks.gorge_metres > 0 && landmarks.gorge_width_permille > 0 {
		patch := landmark_ramp(-reading.mask, i64(landmarks.gorge_mask_percent) * NOISE_ONE / 100, fade)
		if patch > 0 && relief > floor {
			gorge = landmark_gorge(generation, reading, patch, relief - floor)
		}
	}
	if landmarks.mesa_metres > 0 {
		patch := landmark_ramp(reading.mask, i64(landmarks.mesa_mask_percent) * NOISE_ONE / 100, fade)
		if patch > 0 {
			strength := patch * (landform_curve(landmarks.region_mesas_percent, reading.region, NOISE_ONE) / 100) / NOISE_ONE * reading.wildness / NOISE_ONE
			if strength > 0 {
				raise = landmark_mesa_raise(generation, point, reading.hill, strength)
			}
		}
	}
	site_raise, site_cut: i64
	site_raise, site_cut, carve = landmark_site_relief(generation, point)
	if carve.site.kind in CARVING_KINDS {
		carve.ground = min(relief + raise, generation.relief_highest)
	}
	result = min(relief + raise + site_raise, generation.relief_highest)
	if gorge > 0 {
		result = min(result, max(relief - gorge, floor))
	}
	if site_cut > 0 && result > floor {
		result = max(result - site_cut, floor)
	}
	return
}

// The gorge's cut in a patch of strength patch, over ground above_floor
// over the floor: only ground at least half the depth over it is cut,
// fully from the whole depth, then the region's share and the wildness.
landmark_gorge :: proc(generation: Planet_Generation, reading: Landform_Reading, patch, above_floor: i64) -> i64 {
	landmarks := generation.landmarks
	depth := metres_to_position_units(i64(landmarks.gorge_metres))
	strength := patch * landmark_ramp(above_floor, depth / 2, depth / 2) / NOISE_ONE
	if strength > 0 {
		strength = strength * (landform_curve(landmarks.region_gorges_percent, reading.region, NOISE_ONE) / 100) / NOISE_ONE * reading.wildness / NOISE_ONE
	}
	if strength <= 0 {
		return 0
	}
	return landmark_gorge_cut(generation, reading, strength)
}

// (value - threshold) / fade clamped to 0 to 1, in NOISE_ONE.
landmark_ramp :: proc(value, threshold, fade: i64) -> i64 {
	return clamp((value - threshold) * NOISE_ONE / fade, 0, NOISE_ONE)
}

// The cut along the zero lines of the gorge noise, read at the warped
// point and meandering with the hills: a flat floor, then walls rising
// with the root to none at the width. Width and depth go by the root of
// the strength, so a patch's edge narrows the gorge as it shallows. At
// least one unit inside, so the band clips what the mesas and the sites
// raise.
landmark_gorge_cut :: proc(generation: Planet_Generation, reading: Landform_Reading, strength: i64) -> i64 {
	landmarks := generation.landmarks
	root := i64(integer_square_root(u64(strength * NOISE_ONE)))
	width := i64(landmarks.gorge_width_permille) * NOISE_ONE / 1000 * root / NOISE_ONE
	if width <= 0 {
		return 0
	}
	noise := gradient_noise(generation_seed.hash_combine(generation.landmark_seed, 1), reading.warped, metres_to_position_units(i64(landmarks.gorge_wavelength_metres)))
	noise = abs(noise + i64(landmarks.gorge_meander_percent) * reading.hill / 100)
	if noise >= width {
		return 0
	}
	across := noise * NOISE_ONE / width
	floor := i64(landmarks.gorge_floor_percent) * NOISE_ONE / 100
	shape: i64 = NOISE_ONE
	if across > floor {
		shape = i64(integer_square_root(u64((NOISE_ONE - across) * NOISE_ONE / (NOISE_ONE - floor) * NOISE_ONE)))
	}
	return max(metres_to_position_units(i64(landmarks.gorge_metres)) * shape / NOISE_ONE * root / NOISE_ONE, 1)
}

// Two tiers of mesa_metres where the mesa noise (the point unwarped: the
// warp drew the mesas into ribbons) roughened by the hills passes the
// threshold and the threshold plus the tier, each edge steep. A weaker
// strength raises the threshold, so the patch's edge holds smaller mesas,
// never lower ones.
landmark_mesa_raise :: proc(generation: Planet_Generation, point: [3]i64, hill, strength: i64) -> i64 {
	landmarks := generation.landmarks
	noise := gradient_noise(generation_seed.hash_combine(generation.landmark_seed, 2), point, metres_to_position_units(i64(landmarks.mesa_wavelength_metres)))
	noise += i64(landmarks.mesa_rough_percent) * hill / 100
	return mesa_raise_at(landmarks, noise, strength)
}

// The mesas' raise at the roughened noise and the strength, which it
// never falls with in either (the box bound reads it at the ends of their
// ranges, 0314).
mesa_raise_at :: proc(landmarks: Planet_Landmarks, noise, strength: i64) -> i64 {
	threshold := i64(landmarks.mesa_threshold_percent) * NOISE_ONE / 100 + (NOISE_ONE - strength) * MESA_SHRINK_PERCENT / 100
	if noise <= threshold {
		return 0
	}
	edge := i64(landmarks.mesa_edge_permille) * NOISE_ONE / 1000
	tier := i64(landmarks.mesa_tier_percent) * NOISE_ONE / 100
	tiers := noise_fade(landmark_ramp(noise, threshold, edge)) + noise_fade(landmark_ramp(noise, threshold + tier, edge))
	return metres_to_position_units(i64(landmarks.mesa_metres)) * tiers / NOISE_ONE
}

// The raise (a spire, a butte or a carving kind) or the cut (a sinkhole)
// of the point's site; 0, 0 without a site or outside it. A carving
// site's column is weathered by its two noises (its outline, its raise)
// and comes with its carve, its ground left for landmark_relief.
landmark_site_relief :: proc(generation: Planet_Generation, point: [3]i64) -> (raise, cut: i64, carve: Landmark_Carve) {
	site := landmark_site_at(generation, point)
	if site.kind == .None {
		return
	}
	u, along, across, inside := landmark_site_reading(generation, site, point)
	if !inside {
		return
	}
	if site.kind in CARVING_KINDS {
		return landmark_carving_relief(generation, site, point, u, along, across)
	}
	height := site.height * landmark_site_shape(site.kind, u) / NOISE_ONE
	if site.kind == .Sinkhole {
		return 0, height, {}
	}
	return height, 0, {}
}

// A carving site's raise and carve at a point inside its reading: the
// relief noise roughens the outline, weighted by 1 - u² as the wobble
// (landmark_site_reading) so it vanishes at the rim, where the reading's
// reach already cut and a roughening inward left a step; a grotto's
// mouth side falls as a face, and the raise is roughened by the relief
// noise (a grotto's by the shape noise too); nothing once the weathered
// u reaches the edge.
landmark_carving_relief :: proc(generation: Planet_Generation, site: Landmark_Site, point: [3]i64, reading_u, along, across: i64) -> (raise, cut: i64, carve: Landmark_Carve) {
	relief_noise := gradient_noise(generation_seed.hash_combine(generation.landmark_seed, 9), point, max(site.radius * CARVE_RELIEF_WAVE_PERCENT / 100, metres_to_position_units(CARVE_RELIEF_LEAST_WAVE_METRES)))
	shape_noise := gradient_noise(generation_seed.hash_combine(generation.landmark_seed, 10), point, max(site.radius * CARVE_SHAPE_WAVE_PERCENT / 100, metres_to_position_units(CARVE_SHAPE_LEAST_WAVE_METRES)))
	weight := max(NOISE_ONE - reading_u * reading_u / NOISE_ONE, 0)
	u := reading_u * (100 * NOISE_ONE + CARVE_OUTLINE_ROUGH_PERCENT * relief_noise * weight / NOISE_ONE) / (100 * NOISE_ONE)
	if site.kind == .Grotto && along < 0 {
		u = u * (1000 * NOISE_ONE - GROTTO_FACE_PERMILLE * along * NOISE_ONE / landmark_site_outer(site)) / (1000 * NOISE_ONE)
	}
	if u >= NOISE_ONE {
		return
	}
	raise = carve_rough(site.height * landmark_site_shape(site.kind, u) / NOISE_ONE, CARVE_RELIEF_ROUGH_PERCENT, relief_noise)
	if site.kind == .Grotto {
		raise = carve_rough(raise, GROTTO_KNOLL_ROUGH_PERCENT, shape_noise)
	}
	carve = Landmark_Carve {
		site         = site,
		raise        = raise,
		u            = u,
		along        = along,
		across       = across,
		relief_noise = relief_noise,
		shape_noise  = shape_noise,
	}
	return
}

// The most a site of a carving kind raises (the box bound, 0314): the
// shape's share is at most NOISE_ONE and each roughening at most its
// percent, a grotto's two of them.
landmark_raise_most :: proc(site: Landmark_Site) -> i64 {
	return site.height * (100 + CARVE_RELIEF_ROUGH_PERCENT) * (100 + GROTTO_KNOLL_ROUGH_PERCENT) / 10000 + 2
}

// The value moved by percent of itself at the noise's full swing.
carve_rough :: proc(value, percent, noise: i64) -> i64 {
	return value * (100 * NOISE_ONE + percent * noise) / (100 * NOISE_ONE)
}

// The site of the point's lattice cube, kind None when there is none or
// it cannot reach the point. One lattice hash and no root for most points.
landmark_site_at :: proc(generation: Planet_Generation, point: [3]i64) -> Landmark_Site {
	spacing := metres_to_position_units(i64(generation.landmarks.site_spacing_metres))
	cell: [3]i64
	for axis in 0 ..< 3 {
		cell[axis] = floor_divide_i64(point[axis], spacing)
	}
	site, candidate := landmark_site_candidate(generation, cell)
	if site.kind == .None || !landmark_candidate_near(generation, site, candidate, point) {
		return {}
	}
	return place_landmark_site(generation, cell, site, candidate)
}

// The cell's site before it is placed: its kind by the cumulative shares,
// None past them, its hash, radius and stretch, and its jittered point in
// the cube, off the sphere. No root.
landmark_site_candidate :: proc(generation: Planet_Generation, cell: [3]i64) -> (site: Landmark_Site, candidate: [3]i64) {
	landmarks := generation.landmarks
	spacing := metres_to_position_units(i64(landmarks.site_spacing_metres))
	hash := hash_lattice(generation_seed.hash_combine(generation.landmark_seed, 8), cell)
	draw := generation_seed.hash_combine(hash, 1)
	site.kind = landmark_kind_of_roll(landmarks, int(draw % 100))
	if site.kind == .None {
		return
	}
	site.hash = hash
	if site.kind == .Arch {
		// A fin: its half thickness the radius, so its outer reach along
		// its axis is half its length.
		site.stretch_percent = ARCH_LEAST_STRETCH_PERCENT + i64((draw >> 32) % u64(ARCH_MOST_STRETCH_PERCENT - ARCH_LEAST_STRETCH_PERCENT + 1))
		site.radius = hash_metres_range(draw >> 8, landmarks.arch_length_metres) / 2 * 100 / site.stretch_percent
	} else {
		radius, most_stretch_percent := landmark_kind_radius(landmarks, site.kind)
		site.radius = hash_metres_range(draw >> 8, radius)
		site.stretch_percent = 100 + i64((draw >> 32) % u64(most_stretch_percent - 100 + 1))
	}
	for axis in 0 ..< 3 {
		jitter := i64((hash >> uint(axis * SITE_JITTER_BITS)) & ((1 << SITE_JITTER_BITS) - 1))
		candidate[axis] = cell[axis] * spacing + ((jitter * spacing) >> SITE_JITTER_BITS)
	}
	return
}

// The kind a roll of 0 to 99 draws by the cumulative shares spire,
// butte, sinkhole, arch, grotto and mushroom rock; None past them (the
// empty cubes).
landmark_kind_of_roll :: proc(landmarks: Planet_Landmarks, roll: int) -> Landmark_Kind {
	shares := [Landmark_Kind]int {
		.None     = 0,
		.Spire    = landmarks.spire_percent,
		.Butte    = landmarks.butte_percent,
		.Sinkhole = landmarks.sinkhole_percent,
		.Arch     = landmarks.arch_percent,
		.Grotto   = landmarks.grotto_percent,
		.Mushroom = landmarks.mushroom_percent,
	}
	below := 0
	for share, kind in shares {
		below += share
		if kind != .None && roll < below {
			return kind
		}
	}
	return .None
}

// A kind's radius pair and its most stretch; an arch's is drawn from its
// length (landmark_site_candidate).
landmark_kind_radius :: proc(landmarks: Planet_Landmarks, kind: Landmark_Kind) -> (radius: [2]int, most_stretch_percent: int) {
	switch kind {
	case .None, .Arch:
	case .Spire:
		return landmarks.spire_radius_metres, SPIRE_STRETCH_PERCENT
	case .Butte:
		return landmarks.butte_radius_metres, landmarks.butte_stretch_percent
	case .Sinkhole:
		return landmarks.sinkhole_radius_metres, SINKHOLE_STRETCH_PERCENT
	case .Grotto:
		return landmarks.grotto_radius_metres, GROTTO_STRETCH_PERCENT
	case .Mushroom:
		return landmarks.mushroom_radius_metres, MUSHROOM_STRETCH_PERCENT
	}
	return {}, 100
}

// A kind's height pair (a sinkhole's depth).
landmark_kind_height :: proc(landmarks: Planet_Landmarks, kind: Landmark_Kind) -> [2]int {
	switch kind {
	case .None:
	case .Spire:
		return landmarks.spire_metres
	case .Butte:
		return landmarks.butte_metres
	case .Sinkhole:
		return landmarks.sinkhole_metres
	case .Arch:
		return landmarks.arch_metres
	case .Grotto:
		return landmarks.grotto_metres
	case .Mushroom:
		return landmarks.mushroom_metres
	}
	return {}
}

// A length from the range's least to its most metres, drawn by the hash.
hash_metres_range :: proc(hash: u64, range: [2]int) -> i64 {
	least := metres_to_position_units(i64(range[0]))
	most := metres_to_position_units(i64(range[1]))
	return least + i64(hash % u64(most - least + 1))
}

// The farthest the site reaches from its centre: its radius stretched.
landmark_site_outer :: proc(site: Landmark_Site) -> i64 {
	return site.radius * site.stretch_percent / 100
}

// Whether the candidate's site may reach a point on the sphere: the
// candidate's distance from the point's radial against the site's reach,
// widened by the most the candidate lies off the sphere (it lies within
// two spacings of the point) and by 4 units before and after, which
// cover the rounding of the placed centre. The distance is exact, its
// square times the point's squared length in i128, so it drops no site
// the point lies in at any value the bounds allow, and needs no root.
landmark_candidate_near :: proc(generation: Planet_Generation, site: Landmark_Site, candidate, point: [3]i64) -> bool {
	spacing := metres_to_position_units(i64(generation.landmarks.site_spacing_metres))
	offset := candidate - point
	along := i128(offset.x) * i128(point.x) + i128(offset.y) * i128(point.y) + i128(offset.z) * i128(point.z)
	length_squared := i128(point.x) * i128(point.x) + i128(point.y) * i128(point.y) + i128(point.z) * i128(point.z)
	offset_squared := i128(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
	widened := i128((landmark_site_outer(site) + 4) * (generation.radius + 2 * spacing) / generation.radius + 4)
	return offset_squared * length_squared - along * along < widened * widened * length_squared
}

// The candidate projected onto the sphere with its height drawn, or None
// when its disc leaves its cube (so a point reads one cube) or reaches
// into the calm circle round the home.
place_landmark_site :: proc(generation: Planet_Generation, cell: [3]i64, site: Landmark_Site, candidate: [3]i64) -> Landmark_Site {
	spacing := metres_to_position_units(i64(generation.landmarks.site_spacing_metres))
	distance := vector_length(candidate)
	if distance == 0 {
		return {}
	}
	placed := site
	placed.centre = candidate * generation.radius / distance
	outer := landmark_site_outer(site)
	for axis in 0 ..< 3 {
		within := placed.centre[axis] - cell[axis] * spacing
		if within < outer || within > spacing - outer {
			return {}
		}
	}
	calm := metres_to_position_units(i64(generation.landforms.calm_metres)) + outer
	if squared_chord(placed.centre, generation.landform_home) < calm * calm {
		return {}
	}
	placed.height = hash_metres_range(generation_seed.hash_combine(site.hash, 3), landmark_kind_height(generation.landmarks, site.kind))
	return placed
}

// The unit tangent at the site it stretches along, drawn by its hash.
landmark_site_axis :: proc(site: Landmark_Site, radius: i64) -> [3]i64 {
	hash := generation_seed.hash_combine(site.hash, 5)
	drawn := [3]i64{i64(hash & 0xFFFFF) - (1 << 19), i64((hash >> 20) & 0xFFFFF) - (1 << 19), i64((hash >> 40) & 0xFFFFF) - (1 << 19)}
	axis, _ := normalize_fixed(fixed_cross(site.centre * UNIT_VECTOR_ONE / radius, drawn))
	return axis
}

// The point's distance from the site's centre over its radius in
// NOISE_ONE, the part along the axis shrunk by the stretch and the
// outline wobbled by a noise of the site's radius, weighted by 1 - u²
// so it vanishes at the rim (where the reach already cut, a wobble
// inward left a step), with the offsets along the axis and across it in
// position units; inside is u under NOISE_ONE, and beyond the site's
// reach u is NOISE_ONE without a root.
landmark_site_reading :: proc(generation: Planet_Generation, site: Landmark_Site, point: [3]i64) -> (u, along, across: i64, inside: bool) {
	outer := landmark_site_outer(site)
	offset := point - site.centre
	squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
	if squared >= outer * outer {
		return NOISE_ONE, 0, 0, false
	}
	axis := landmark_site_axis(site, generation.radius)
	along = (offset.x * axis.x + offset.y * axis.y + offset.z * axis.z) / UNIT_VECTOR_ONE
	across_squared := max(squared - along * along, 0)
	across = i64(integer_square_root(u64(across_squared)))
	stretched := across_squared + along * along * 10000 / (site.stretch_percent * site.stretch_percent)
	unwobbled := i64(integer_square_root(u64(stretched))) * NOISE_ONE / site.radius
	u = unwobbled
	wobble_percent := i64(generation.landmarks.wobble_percent)
	if wobble_percent > 0 {
		wobble := gradient_noise(generation_seed.hash_combine(generation.landmark_seed, 7), point, max(site.radius, metres_to_position_units(4)))
		// Under the reach unwobbled is below 4 NOISE_ONE (the stretch's
		// most), so its square and the products stay far inside i64.
		weight := max(NOISE_ONE - unwobbled * unwobbled / NOISE_ONE, 0)
		u = unwobbled * (100 * NOISE_ONE + wobble_percent * wobble * weight / NOISE_ONE) / (100 * NOISE_ONE)
	}
	return u, along, across, u < NOISE_ONE
}

// The kind's height share at u, NOISE_ONE at the centre to 0 at the
// radius (Landmark_Profile): the cap crowned, the wall falling from the
// cap's edge.
landmark_site_shape :: proc(kind: Landmark_Kind, u: i64) -> i64 {
	profiles := LANDMARK_PROFILES
	profile := profiles[kind]
	cap_end := profile.cap * NOISE_ONE / 1000
	wall_end := profile.wall_end * NOISE_ONE / 1000
	talus := profile.talus * NOISE_ONE / 1000
	crown := profile.crown * NOISE_ONE / 1000
	switch {
	case u >= NOISE_ONE:
		return 0
	case u <= cap_end:
		if cap_end == 0 {
			return NOISE_ONE
		}
		way := u * NOISE_ONE / cap_end
		return NOISE_ONE - crown * way / NOISE_ONE * way / NOISE_ONE
	case u <= wall_end:
		fade := noise_fade((u - cap_end) * NOISE_ONE / (wall_end - cap_end))
		return talus + (NOISE_ONE - crown - talus) * (NOISE_ONE - fade) / NOISE_ONE
	}
	beyond := (u - wall_end) * NOISE_ONE / (NOISE_ONE - wall_end)
	return talus * (NOISE_ONE - beyond) / NOISE_ONE * (NOISE_ONE - beyond) / NOISE_ONE
}

// An ellipse's signed distance, approximated: the shorter semi axis times
// the root of the scaled squares less one; negative inside.
ellipse_distance :: proc(x, semi_x, y, semi_y: i64) -> i64 {
	q := x * x / semi_x * NOISE_ONE / semi_x + y * y / semi_y * NOISE_ONE / semi_y
	return min(semi_x, semi_y) * (i64(integer_square_root(u64(q * NOISE_ONE))) - NOISE_ONE) / NOISE_ONE
}

// The carve's signed distance at a height over the carve's ground,
// negative in the carved air; nothing under the ground is carved, and a
// column outside every carving site is far from any carve.
landmark_carve_distance :: proc(carve: Landmark_Carve, height: i64) -> i64 {
	inside: i64 = 1 << 40
	switch carve.site.kind {
	case .None, .Spire, .Butte, .Sinkhole:
	case .Arch:
		inside = arch_carve_distance(carve, height)
	case .Grotto:
		inside = grotto_carve_distance(carve, height)
	case .Mushroom:
		inside = mushroom_carve_distance(carve, height)
	}
	return max(inside, -height)
}

// The opening through the fin: an ellipse across it, its semi axes moved
// by the shape noise, its centre along the fin by the relief noise, its
// width narrowing towards its crown.
arch_carve_distance :: proc(carve: Landmark_Carve, height: i64) -> i64 {
	site := carve.site
	semi_along := carve_rough(landmark_site_outer(site) * ARCH_OPENING_WIDTH_PERMILLE / 1000, ARCH_OPENING_ROUGH_PERCENT, carve.shape_noise)
	semi_up := carve_rough(site.height * ARCH_OPENING_HEIGHT_PERMILLE / 1000, ARCH_OPENING_ROUGH_PERCENT * 2 / 3, carve.shape_noise)
	along := carve.along - semi_along * ARCH_SKEW_PERCENT / 100 * carve.relief_noise / NOISE_ONE
	way_up := clamp(height * NOISE_ONE / semi_up, 0, NOISE_ONE)
	along = along * NOISE_ONE / (NOISE_ONE - ARCH_TAPER_PERMILLE * way_up / 1000)
	return ellipse_distance(along, semi_along, height, semi_up)
}

// A chamber under the knoll's centre and a tunnel from it out through
// the face on the mouth's side (along below 0), meandering across.
grotto_carve_distance :: proc(carve: Landmark_Carve, height: i64) -> i64 {
	site := carve.site
	width := carve_rough(site.radius * GROTTO_TUNNEL_PERMILLE / 1000, GROTTO_ROUGH_PERCENT, carve.shape_noise)
	across := carve.across - width * GROTTO_MEANDER_PERMILLE / 1000 * carve.relief_noise / NOISE_ONE
	tunnel := max(ellipse_distance(across, width, height, width * GROTTO_TUNNEL_HEIGHT_PERMILLE / 1000), carve.along)
	flat := i64(integer_square_root(u64(carve.along * carve.along + carve.across * carve.across)))
	chamber_radius := carve_rough(site.radius * GROTTO_CHAMBER_PERMILLE / 1000, GROTTO_ROUGH_PERCENT, carve.shape_noise)
	chamber_height := carve_rough(site.height * GROTTO_CHAMBER_HEIGHT_PERMILLE / 1000, GROTTO_ROUGH_PERCENT, carve.shape_noise)
	return min(tunnel, ellipse_distance(flat, chamber_radius, height, chamber_height))
}

// The air round the stem and under the cap: the stem narrowing towards
// its foot, the cap's underside level under the crowned top's rim and
// thicker towards the stem; where the cap would thin under
// MUSHROOM_LEAST_CAP or close the gap under it the column is carved
// whole, which leaves the rim ragged.
mushroom_carve_distance :: proc(carve: Landmark_Carve, height: i64) -> i64 {
	site := carve.site
	profiles := LANDMARK_PROFILES
	rim := site.height * MUSHROOM_CAP_PERMILLE / 1000
	nominal := site.height - rim
	way_up := clamp(height * NOISE_ONE / max(nominal, 1), 0, NOISE_ONE)
	stem := carve_rough(site.radius * MUSHROOM_STEM_PERMILLE / 1000, MUSHROOM_STEM_ROUGH_PERCENT, carve.shape_noise) * (1000 * NOISE_ONE - MUSHROOM_FOOT_PERMILLE * (NOISE_ONE - way_up)) / (1000 * NOISE_ONE)
	thickness := rim * (100 * NOISE_ONE + MUSHROOM_THICKEN_PERCENT * (NOISE_ONE - min(carve.u, NOISE_ONE)) + MUSHROOM_UNDER_ROUGH_PERCENT * carve.shape_noise) / (100 * NOISE_ONE)
	under := carve_rough(site.height * (1000 - profiles[.Mushroom].crown) / 1000, CARVE_RELIEF_ROUGH_PERCENT, carve.relief_noise) - thickness
	if under < metres_to_position_units(MUSHROOM_CLEARANCE_METRES) || carve.raise - under < MUSHROOM_LEAST_CAP {
		under = carve.raise + metres_to_position_units(1)
	}
	return max(stem - carve.u * site.radius / NOISE_ONE, height - under)
}
