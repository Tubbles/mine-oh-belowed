package game

import "generation_seed"

// The landmarks of a planet (work item 0323, doc/architecture.md, World
// generation): gorges, mesas with their cliff bands, and sites (spires,
// buttes and sinkholes), the last term of uncratered_relief, after
// Minecraft's canyon carver and its badlands. The gorges and the mesas lie
// in patches of the landforms' first warp noise (Landform_Reading.mask),
// so they cost no noise outside them and never overlap; the sites lie on
// a jittered lattice, one per cube at most, each disc inside its cube, so
// a point reads one cube. Every term scales with home_wildness or keeps
// clear of the calm circle. Raises clamp at the bound's highest and cuts
// stop at a floor over the sea, so the relief stays within the planet's
// bound. Integers and fixed point only, a pure function of the point, as
// the rest of the relief. Off at the zero Planet_Landmarks.

// The bits of the site hash that jitter each axis.
SITE_JITTER_BITS :: 21
// How far a patch's weak edge raises the mesas' threshold, percent of
// the noise's range, so the patch ends in smaller mesas, never lower ones.
MESA_SHRINK_PERCENT :: 40

Landmark_Kind :: enum u8 {
	None,
	Spire,
	Butte,
	Sinkhole,
}

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
Landmark_Profile :: struct {
	cap, wall_end, talus: i64,
}

LANDMARK_PROFILES :: [Landmark_Kind]Landmark_Profile {
	.None     = {},
	.Spire    = {80, 450, 180},
	.Butte    = {520, 640, 220},
	.Sinkhole = {300, 700, 80},
}

// The relief with the landmarks: the gorges cut, the mesas and the sites
// raise or cut, each where its patch, its region share and the wildness
// leave it any strength. The mask comes first, so a patch's ramp of 0
// skips its curve and its noise. Raises clamp at the bound's highest and
// cuts stop at the floor, dry_metres over the sea (the bound's lowest at
// least), so the relief stays within the planet's bound.
landmark_relief :: proc(generation: Planet_Generation, point: [3]i64, relief: i64, reading: Landform_Reading) -> i64 {
	landmarks := generation.landmarks
	if landmarks.site_spacing_metres == 0 || reading.wildness == 0 {
		return relief
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
	site_raise, site_cut := landmark_site_relief(generation, point)
	result := min(relief + raise + site_raise, generation.relief_highest)
	if gorge > 0 {
		result = min(result, max(relief - gorge, floor))
	}
	if site_cut > 0 && result > floor {
		result = max(result - site_cut, floor)
	}
	return result
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
	threshold := i64(landmarks.mesa_threshold_percent) * NOISE_ONE / 100 + (NOISE_ONE - strength) * MESA_SHRINK_PERCENT / 100
	if noise <= threshold {
		return 0
	}
	edge := i64(landmarks.mesa_edge_permille) * NOISE_ONE / 1000
	tier := i64(landmarks.mesa_tier_percent) * NOISE_ONE / 100
	tiers := noise_fade(landmark_ramp(noise, threshold, edge)) + noise_fade(landmark_ramp(noise, threshold + tier, edge))
	return metres_to_position_units(i64(landmarks.mesa_metres)) * tiers / NOISE_ONE
}

// The raise (a spire or a butte) or the cut (a sinkhole) of the point's
// site; 0, 0 without a site or outside it.
landmark_site_relief :: proc(generation: Planet_Generation, point: [3]i64) -> (raise, cut: i64) {
	site := landmark_site_at(generation, point)
	if site.kind == .None {
		return 0, 0
	}
	u, inside := landmark_site_u(generation, site, point)
	if !inside {
		return 0, 0
	}
	height := site.height * landmark_site_shape(site.kind, u) / NOISE_ONE
	if site.kind == .Sinkhole {
		return 0, height
	}
	return height, 0
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
	radius, most_stretch_percent := landmark_kind_radius(landmarks, site.kind)
	site.hash = hash
	site.radius = hash_metres_range(draw >> 8, radius)
	site.stretch_percent = 100 + i64((draw >> 32) % u64(most_stretch_percent - 100 + 1))
	for axis in 0 ..< 3 {
		jitter := i64((hash >> uint(axis * SITE_JITTER_BITS)) & ((1 << SITE_JITTER_BITS) - 1))
		candidate[axis] = cell[axis] * spacing + ((jitter * spacing) >> SITE_JITTER_BITS)
	}
	return
}

// The kind a roll of 0 to 99 draws by the cumulative shares spire, butte
// and sinkhole; None past them (0324's kinds and the empty cubes).
landmark_kind_of_roll :: proc(landmarks: Planet_Landmarks, roll: int) -> Landmark_Kind {
	switch {
	case roll < landmarks.spire_percent:
		return .Spire
	case roll < landmarks.spire_percent + landmarks.butte_percent:
		return .Butte
	case roll < landmarks.spire_percent + landmarks.butte_percent + landmarks.sinkhole_percent:
		return .Sinkhole
	}
	return .None
}

// A kind's radius pair and its most stretch.
landmark_kind_radius :: proc(landmarks: Planet_Landmarks, kind: Landmark_Kind) -> (radius: [2]int, most_stretch_percent: int) {
	switch kind {
	case .None:
	case .Spire:
		return landmarks.spire_radius_metres, SPIRE_STRETCH_PERCENT
	case .Butte:
		return landmarks.butte_radius_metres, landmarks.butte_stretch_percent
	case .Sinkhole:
		return landmarks.sinkhole_radius_metres, SINKHOLE_STRETCH_PERCENT
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
// outline wobbled by a noise of the site's radius, the wobble weighted by
// 1 - u² so it vanishes at the rim and the site meets the ground round
// it; inside is u under NOISE_ONE, and beyond the site's reach u is
// NOISE_ONE without a root.
landmark_site_u :: proc(generation: Planet_Generation, site: Landmark_Site, point: [3]i64) -> (u: i64, inside: bool) {
	outer := landmark_site_outer(site)
	offset := point - site.centre
	squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
	if squared >= outer * outer {
		return NOISE_ONE, false
	}
	axis := landmark_site_axis(site, generation.radius)
	along := (offset.x * axis.x + offset.y * axis.y + offset.z * axis.z) / UNIT_VECTOR_ONE
	across_squared := max(squared - along * along, 0)
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
	return u, u < NOISE_ONE
}

// The kind's height share at u, NOISE_ONE on the cap to 0 at the radius
// (Landmark_Profile).
landmark_site_shape :: proc(kind: Landmark_Kind, u: i64) -> i64 {
	profiles := LANDMARK_PROFILES
	profile := profiles[kind]
	cap_end := profile.cap * NOISE_ONE / 1000
	wall_end := profile.wall_end * NOISE_ONE / 1000
	talus := profile.talus * NOISE_ONE / 1000
	switch {
	case u >= NOISE_ONE:
		return 0
	case u <= cap_end:
		return NOISE_ONE
	case u <= wall_end:
		fade := noise_fade((u - cap_end) * NOISE_ONE / (wall_end - cap_end))
		return talus + (NOISE_ONE - talus) * (NOISE_ONE - fade) / NOISE_ONE
	}
	beyond := (u - wall_end) * NOISE_ONE / (NOISE_ONE - wall_end)
	return talus * (NOISE_ONE - beyond) / NOISE_ONE * (NOISE_ONE - beyond) / NOISE_ONE
}
