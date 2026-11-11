package game

import "generation_seed"

// The caves and the walls' undercuts (work item 0327, doc/architecture.md,
// World generation), after Minecraft 1.18's noise caves: tunnels along
// the zero lines of a noise on levels at fixed heights, which the terrain
// cuts into mouths on its walls, and chambers where a squashed noise lies
// low under a roof; notches at half a gorge wall's or a mesa cliff's
// height. A sample's depth is the least of the column's (0324) and theirs
// (sample_depth); the cave share comes from the landforms' reading, so no
// cave lies in the calm circle; none deeper than the shell, under the sea
// level plus the dry margin or by a lake's water. Integers and fixed
// point, a pure function of the position and the record. The box bound's
// ranges of them are generation_planet_bound.odin's.

// A gradient noise's median slope at its zero lines, NOISE_ONE per
// wavelength in percent, which turns a noise into metres.
CAVE_NOISE_SLOPE_PERCENT :: 120
// The presence's and the undercut noise's ramp, percent of the noise.
CAVE_PRESENCE_FADE_PERCENT :: 6
// The chambers' noise runs this much faster along the radial, so they are
// wider than tall.
CAVE_CHAMBER_SQUASH_PERCENT :: 160
// No cave or notch within the margin of a lake's water (its mask under its
// level, planet_lake_water_distance), fading in over the fade beyond it.
CAVE_LAKE_MARGIN_METRES :: 4
CAVE_LAKE_FADE_METRES :: 12
// A chunk's or a grid's box widened by this lists every lake the fade
// reads at its samples.
CAVE_LAKE_LIST_METRES :: CAVE_LAKE_MARGIN_METRES + CAVE_LAKE_FADE_METRES
// A mask row within the reach fits one word (planet_lake_mask_run).
#assert(2 * ((CAVE_LAKE_LIST_METRES + LAKE_CELL_METRES - 1) / LAKE_CELL_METRES) + 1 <= 64)
// The distance of no cave.
CAVE_NONE :: i64(1) << 40
// A notch is computed this far past its reach, where its distance is at
// least 2 m.
UNDERCUT_BAND_METRES :: 4
// A notch the undercut noise leaves shorter than this is none.
UNDERCUT_LEAST_REACH_MILLIMETRES :: 500
// The salts of the caves' noises on Planet_Generation.cave_seed.
CAVE_PRESENCE_SALT :: 0
CAVE_LEVEL_SALT :: 1
CAVE_TUNNEL_SALT :: 2
CAVE_CHAMBER_SALT :: 3
UNDERCUT_SALT :: 4

// A column's cave strength (0 to NOISE_ONE, the share times the presence)
// and its levels' swing in position units.
Cave_Column :: struct {
	strength, offset: i64,
}

// A column's notch, position units: its offset from the wall's face at
// the notch's centre (positive into the rock), the centre's height over
// the radius, the reach (0 none) and the half height.
Wall_Undercut :: struct {
	offset, centre, reach, half_height: i64,
}

// What landmark_gorge_cut reads: the cut, the meandered noise's absolute
// value, the width (both in noise units) and the strength's root.
Gorge_Cut :: struct {
	cut, noise, width, root: i64,
}

// A noise of the caves at a point: its salt on the caves' seed, its
// wavelength in metres.
planet_cave_noise :: proc(generation: Planet_Generation, salt: u64, point: [3]i64, wavelength_metres: int) -> i64 {
	return gradient_noise(generation_seed.hash_combine(generation.cave_seed, salt), point, metres_to_position_units(i64(wavelength_metres)))
}

// A noise (or its offset from a level of it) as a distance in position
// units at the noise's median slope over its wavelength.
cave_noise_distance :: proc(noise, wavelength: i64) -> i64 {
	return noise * wavelength / (CAVE_NOISE_SLOPE_PERCENT * NOISE_ONE / 100)
}

// The caves' share at a column: the region's knots times the wildness, 0
// without caves or in the calm circle.
cave_share :: proc(generation: Planet_Generation, reading: Landform_Reading) -> i64 {
	if generation.caves == {} || reading.wildness == 0 {
		return 0
	}
	share := landform_curve(generation.caves.region_caves_percent, reading.region, NOISE_ONE) / 100
	if share <= 0 {
		return 0
	}
	return share * reading.wildness / NOISE_ONE
}

// The column's cave strength under the presence noise and its levels'
// swing: two noises in a column with a share, none elsewhere.
cave_column :: proc(generation: Planet_Generation, column: Surface_Column, on_sphere: [3]i64) -> Cave_Column {
	if column.cave_share <= 0 {
		return {}
	}
	caves := generation.caves
	presence := planet_cave_noise(generation, CAVE_PRESENCE_SALT, on_sphere, caves.presence_wavelength_metres)
	strength := column.cave_share * landmark_ramp(presence, i64(caves.presence_threshold_percent) * NOISE_ONE / 100, CAVE_PRESENCE_FADE_PERCENT * NOISE_ONE / 100) / NOISE_ONE
	if strength <= 0 {
		return {}
	}
	return {strength, metres_to_position_units(i64(caves.level_swing_metres)) * planet_cave_noise(generation, CAVE_LEVEL_SALT, on_sphere, caves.level_wavelength_metres) / NOISE_ONE}
}

// The generation a box's samples read: with caves and lakes, a copy whose
// lakes are those meeting the box widened by CAVE_LAKE_LIST_METRES and
// whose tiles are nil, so every sample's fade reads one short list (the
// chunks, the grids); else the generation.
cave_lakes_generation :: proc(generation: Planet_Generation, minimum, maximum: [3]i64) -> Planet_Generation {
	if generation.caves == {} || (len(generation.lakes) == 0 && generation.water_tiles == nil) {
		return generation
	}
	widen := metres_to_position_units(CAVE_LAKE_LIST_METRES)
	samples := generation
	samples.lakes = generation_lakes_meeting_box(generation, minimum - widen, maximum + widen)
	samples.water_tiles = nil
	return samples
}

// NOISE_ONE, lowered by every lake whose bound plus the reach holds the
// position, by its water's distance (cave_lake_fade_of); the least, so
// the order is free. A sample read alone (with tiles) copies no lake: it
// reads the tiles' kept lakes in place (water_tile_cave_lake_fade); a
// chunk or a grid reads its list (cave_lakes_generation), as do 0312's
// features.
cave_lake_fade :: proc(generation: Planet_Generation, position: World_Position, distance: i64, on_sphere: [3]i64) -> i64 {
	if generation.water_tiles != nil {
		return water_tile_cave_lake_fade(generation.water_tiles, generation, position, distance, on_sphere)
	}
	fade: i64 = NOISE_ONE
	for lake in generation.lakes {
		fade = min(fade, cave_lake_fade_of(generation, lake, position, distance, on_sphere))
		if fade == 0 {
			break
		}
	}
	return fade
}

// One lake's fade at the sample: NOISE_ONE when the position lies outside
// the lake's bound sphere plus the margin and the fade (0312's bound holds
// every water sample, so the water lies farther); else 0 within the
// margin of its water (planet_lake_water_distance), rising to NOISE_ONE
// over the fade.
cave_lake_fade_of :: proc(generation: Planet_Generation, lake: Planet_Lake, position: World_Position, distance: i64, on_sphere: [3]i64) -> i64 {
	margin := metres_to_position_units(CAVE_LAKE_MARGIN_METRES)
	fade_length := metres_to_position_units(CAVE_LAKE_FADE_METRES)
	reach := margin + fade_length
	offset := cast([3]i64)position - lake.bound_centre
	limit := lake.bound_radius + reach
	if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z >= limit * limit {
		return NOISE_ONE
	}
	water := planet_lake_water_distance(lake, generation.radius, distance, on_sphere, reach)
	return clamp((water - margin) * NOISE_ONE / fade_length, 0, NOISE_ONE)
}

// The signed distance of the caves at the sample, negative inside one:
// the column's strength faded by the shell under the relief and by the
// lakes, the least of the tunnel's and the chamber's, kept out of the dry
// level over the sea; CAVE_NONE where the strength is 0. The lakes' fade
// only weakens the strength, which only raises the distance, so a sample
// the unfaded caves leave a spacing or more outside keeps its density
// without the lakes' query: the unfaded distance stands for it there.
cave_distance :: proc(generation: Planet_Generation, cave: Cave_Column, relief: i64, position: World_Position, distance: i64, on_sphere: [3]i64) -> i64 {
	if cave.strength <= 0 {
		return CAVE_NONE
	}
	caves := generation.caves
	height := distance - generation.radius
	depth := relief - height
	strength := cave.strength * cave_shell_fade(caves, depth) / NOISE_ONE
	if strength <= 0 {
		return CAVE_NONE
	}
	tunnel_noise, chamber_noise: i64
	if caves.tunnel_width_millimetres > 0 {
		tunnel_noise = planet_cave_noise(generation, CAVE_TUNNEL_SALT, cast([3]i64)position, caves.tunnel_wavelength_metres)
	}
	if caves.chamber_threshold_percent < 100 {
		chamber_noise = planet_cave_noise(generation, CAVE_CHAMBER_SALT, cave_squashed_point(generation, on_sphere, height), caves.chamber_wavelength_metres)
	}
	dry := generation.sea_radius + metres_to_position_units(i64(caves.dry_metres)) - distance
	unfaded := cave_distance_from(caves, strength, height - cave.offset, depth, tunnel_noise, chamber_noise, dry)
	if unfaded >= generation.spacing {
		return unfaded
	}
	strength = strength * cave_lake_fade(generation, position, distance, on_sphere) / NOISE_ONE
	if strength <= 0 {
		return CAVE_NONE
	}
	return cave_distance_from(caves, strength, height - cave.offset, depth, tunnel_noise, chamber_noise, dry)
}

// The caves' distance at a strength from the swung height, the depth, the
// two noises and the dry level's distance: the least of the tunnel's and
// the chamber's, those on, kept out of the dry level.
cave_distance_from :: proc(caves: Planet_Caves, strength, swung_height, depth, tunnel_noise, chamber_noise, dry: i64) -> i64 {
	tunnel, chamber := CAVE_NONE, CAVE_NONE
	if caves.tunnel_width_millimetres > 0 {
		tunnel = cave_tunnel_distance(caves, strength, swung_height, tunnel_noise)
	}
	if caves.chamber_threshold_percent < 100 {
		chamber = cave_chamber_distance(caves, strength, depth, chamber_noise)
	}
	return max(min(tunnel, chamber), dry)
}

// The shell's fade at a depth under the relief: NOISE_ONE down to the
// shell less CAVE_SHELL_FADE_METRES, 0 from the shell down.
cave_shell_fade :: proc(caves: Planet_Caves, depth: i64) -> i64 {
	return clamp((metres_to_position_units(i64(caves.shell_metres)) - depth) * NOISE_ONE / metres_to_position_units(CAVE_SHELL_FADE_METRES), 0, NOISE_ONE)
}

// The tunnel's distance at the height over the radius less the column's
// swing and the tunnel noise: the offset from the nearest level (half a
// level either way) and the noise as metres across, the cross section an
// ellipse of the width and the height in half axes, narrowed by the
// strength.
cave_tunnel_distance :: proc(caves: Planet_Caves, strength, swung_height, noise: i64) -> i64 {
	level := metres_to_position_units(i64(caves.level_metres))
	up := swung_height - level * floor_divide_i64(swung_height + level / 2, level)
	across := cave_noise_distance(noise, metres_to_position_units(i64(caves.tunnel_wavelength_metres)))
	return cave_tunnel_from(caves, strength, abs(up), abs(across))
}

// The tunnel's distance from the offsets up from its level and across its
// zero line, both 0 or more (cave_tunnel_distance, and the box bound's
// least at the offsets' least).
cave_tunnel_from :: proc(caves: Planet_Caves, strength, up, across: i64) -> i64 {
	width := millimetres_to_position_units(caves.tunnel_width_millimetres)
	stretched := up * width / millimetres_to_position_units(caves.tunnel_height_millimetres)
	return i64(integer_square_root(u64(across * across + stretched * stretched))) - width * strength / NOISE_ONE
}

// The point the chamber noise reads: the point on the sphere moved out by
// the height times the squash less one over the radius, so the noise runs
// CAVE_CHAMBER_SQUASH_PERCENT as fast along the radial.
cave_squashed_point :: proc(generation: Planet_Generation, on_sphere: [3]i64, height: i64) -> [3]i64 {
	squashed: [3]i64
	for axis in 0 ..< 3 {
		squashed[axis] = on_sphere[axis] + on_sphere[axis] * (height * (CAVE_CHAMBER_SQUASH_PERCENT - 100) / 100) / generation.radius
	}
	return squashed
}

// The chamber's distance at the depth under the relief and the chamber
// noise: negative where the noise lies under minus the threshold, which
// a weaker strength raises to none, as metres at the noise's slope,
// raised to keep roof_metres of rock under the relief.
cave_chamber_distance :: proc(caves: Planet_Caves, strength, depth, noise: i64) -> i64 {
	threshold := NOISE_ONE - (NOISE_ONE - i64(caves.chamber_threshold_percent) * NOISE_ONE / 100) * strength / NOISE_ONE
	chamber := cave_noise_distance(noise + threshold, metres_to_position_units(i64(caves.chamber_wavelength_metres)))
	return max(chamber, metres_to_position_units(i64(caves.roof_metres)) - depth)
}

// The notch's signed distance at a height over the radius, negative
// inside its ellipse; CAVE_NONE without a notch. ellipse_distance scales
// by the shorter half axis, so under a notch narrower than it is high it
// falls short of the gap; the gaps to the ellipse's box keep it at least
// them, with the same sign, so no notch changes a sample a spacing or
// more under its bottom (undercut_box_bound's floor).
undercut_distance :: proc(undercut: Wall_Undercut, height: i64) -> i64 {
	if undercut.reach == 0 {
		return CAVE_NONE
	}
	return max(ellipse_distance(undercut.offset, undercut.reach, height - undercut.centre, undercut.half_height), undercut_box_gap(undercut, height))
}

// The gap from a height in the notch's column to the notch's box, its
// reach by twice its half height round the centre; at most its distance.
undercut_box_gap :: proc(undercut: Wall_Undercut, height: i64) -> i64 {
	return max(abs(height - undercut.centre) - undercut.half_height, abs(undercut.offset) - undercut.reach)
}

// A gorge's notch at half its full cut, on the face where the cut is half
// of it (the meandered noise at the middle of landmark_gorge_cut's
// shape), from the relief before the landmarks; none while the undercuts
// are off, outside the gorge's band, under the floor or in a gorge too
// shallow for it.
gorge_undercut :: proc(generation: Planet_Generation, gorge: Gorge_Cut, relief, floor: i64) -> Wall_Undercut {
	caves := generation.caves
	landmarks := generation.landmarks
	if caves.undercut_reach_millimetres == 0 || gorge.width <= 0 {
		return {}
	}
	full := metres_to_position_units(i64(landmarks.gorge_metres)) * gorge.root / NOISE_ONE
	floor_share := i64(landmarks.gorge_floor_percent) * NOISE_ONE / 100
	middle := (NOISE_ONE - (NOISE_ONE - floor_share) / 4) * gorge.width / NOISE_ONE
	offset := cave_noise_distance(gorge.noise - middle, metres_to_position_units(i64(landmarks.gorge_wavelength_metres)))
	centre := relief - full / 2
	reach := millimetres_to_position_units(caves.undercut_reach_millimetres)
	half := millimetres_to_position_units(caves.undercut_height_millimetres)
	if abs(offset) >= reach + metres_to_position_units(UNDERCUT_BAND_METRES) || centre - half < floor || full / 2 < half + metres_to_position_units(1) {
		return {}
	}
	return {offset, centre, reach, half}
}

// A mesa's notch at half a tier's cliff, on the edge's middle nearest the
// roughened noise (tier 0, and tier 1 when the tier is at least the
// edge), from the relief before the landmarks; none while the undercuts
// are off, outside the band or on a tier too low for it.
mesa_undercut :: proc(generation: Planet_Generation, noise, strength, relief: i64) -> Wall_Undercut {
	caves := generation.caves
	landmarks := generation.landmarks
	tier_height := metres_to_position_units(i64(landmarks.mesa_metres))
	reach := millimetres_to_position_units(caves.undercut_reach_millimetres)
	half := millimetres_to_position_units(caves.undercut_height_millimetres)
	if caves.undercut_reach_millimetres == 0 || tier_height / 2 < half + metres_to_position_units(1) {
		return {}
	}
	threshold := i64(landmarks.mesa_threshold_percent) * NOISE_ONE / 100 + (NOISE_ONE - strength) * MESA_SHRINK_PERCENT / 100
	edge := i64(landmarks.mesa_edge_permille) * NOISE_ONE / 1000
	tier := i64(landmarks.mesa_tier_percent) * NOISE_ONE / 100
	band := reach + metres_to_position_units(UNDERCUT_BAND_METRES)
	wavelength := metres_to_position_units(i64(landmarks.mesa_wavelength_metres))
	result: Wall_Undercut
	for index in i64(0) ..< (tier >= edge ? 2 : 1) {
		offset := cave_noise_distance(noise - (threshold + tier * index + edge / 2), wavelength)
		if abs(offset) < band && (result.reach == 0 || abs(offset) < abs(result.offset)) {
			result = {offset, relief + index * tier_height + tier_height / 2, reach, half}
		}
	}
	return result
}

// A found notch's reach times the ramp of the undercut noise at the
// point; none under UNDERCUT_LEAST_REACH_MILLIMETRES. One noise per notch
// column.
undercut_presence :: proc(generation: Planet_Generation, point: [3]i64, undercut: Wall_Undercut) -> Wall_Undercut {
	caves := generation.caves
	noise := planet_cave_noise(generation, UNDERCUT_SALT, point, caves.undercut_wavelength_metres)
	result := undercut
	result.reach = undercut.reach * landmark_ramp(noise, i64(caves.undercut_threshold_percent) * NOISE_ONE / 100, CAVE_PRESENCE_FADE_PERCENT * NOISE_ONE / 100) / NOISE_ONE
	if result.reach < millimetres_to_position_units(UNDERCUT_LEAST_REACH_MILLIMETRES) {
		return {}
	}
	return result
}

// The depth into the ground at the sample: the column's (column_depth), in
// a notch column its least with the notch, whose reach the lakes' fade at
// the position scales (none under UNDERCUT_LEAST_REACH_MILLIMETRES, as
// undercut_presence leaves none, so no sliver of a notch stands at a
// lake's margin), and while the cave's strength is above 0 and the depth
// above minus a spacing its least with the caves' (a deeper air sample's
// density saturates already). The lakes are read at the sample, so a
// chunk's list covers them, and only within a spacing of the notch's box
// at its full reach (undercut_box_gap): the fade only shortens the reach,
// and a notch's distance is at least the gap to its box, so outside it
// the density stays.
sample_depth :: proc(generation: Planet_Generation, column: Surface_Column, cave: Cave_Column, position: World_Position, distance: i64, on_sphere: [3]i64) -> i64 {
	height := distance - generation.radius
	depth := column_depth(column, height)
	if column.undercut.reach > 0 && undercut_box_gap(column.undercut, height) < generation.spacing {
		notch := column.undercut
		notch.reach = notch.reach * cave_lake_fade(generation, position, distance, on_sphere) / NOISE_ONE
		if notch.reach >= millimetres_to_position_units(UNDERCUT_LEAST_REACH_MILLIMETRES) {
			depth = min(depth, undercut_distance(notch, height))
		}
	}
	if cave.strength > 0 && depth > -generation.spacing {
		depth = min(depth, cave_distance(generation, cave, column.relief, position, distance, on_sphere))
	}
	return depth
}

// Whether carved air at the sample lies under ground. True at once for a
// sample roof_metres or more under the relief in a column without a
// notch and outside a carving site: a column's air open to the sky is a
// tunnel's band of at most twice its half height from the top, and
// caves_problem keeps two of the coarsest spacing with caves of rock
// under it, so a chamber is always roofed. Else steps of one spacing up
// the sample's radial while under the relief, true at the first whose
// sample_depth gives ground, false at the top; the same column and cave
// column at every step.
carved_air_roofed :: proc(generation: Planet_Generation, column: Surface_Column, cave: Cave_Column, position: World_Position, distance: i64, on_sphere: [3]i64) -> bool {
	height := distance - generation.radius
	if column.undercut.reach == 0 && column.carve.site.kind not_in CARVING_KINDS && column.relief - height >= metres_to_position_units(i64(generation.caves.roof_metres)) {
		return true
	}
	for step := generation.spacing; height + step < column.relief; step += generation.spacing {
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
