package game

import "core:math"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "generation_seed"

// The debris of the hit (work item 0272, doc/presentation.md, The
// arrival): arrival_debris_pieces clods leave the crater's bowl at the
// hit on parabolas, land between the rim and five crater radii, rest on
// the baked generation's surface and sink away. Presentation only: every
// value is a pure function of the piece's index, the seconds since the
// hit, the world's seed, the baked generation and the pod's frame,
// recomputed every frame, so a joiner or a load sees the same clods and
// the hash never moves.

ARRIVAL_DEBRIS_SALT :: 0x64656272
// The innermost piece leaves at the hit, the outermost this much later.
ARRIVAL_DEBRIS_LAUNCH_SPREAD_SECONDS :: 0.4
// A resting piece sinks into the ground over these seconds.
ARRIVAL_DEBRIS_FADE_SECONDS :: 8.0
// The bound of a piece's launch plus its flight, at the largest crater.
ARRIVAL_DEBRIS_FLIGHT_SECONDS :: 8.0
// A piece's edge, smallest + (largest - smallest) times a hashed share
// squared, so the small ones are many.
ARRIVAL_DEBRIS_SMALLEST_METRES :: 0.15
ARRIVAL_DEBRIS_LARGEST_METRES :: 0.6
// The field shader's tint_scale (data/shaders/field.fs): the tiles are
// mid tones, the palette's tint scaled so carries the colour.
ARRIVAL_DEBRIS_TINT_SCALE :: 2.0
// The share of the pieces whose landing sounds.
ARRIVAL_PATTER_SHARE :: 0.5
// A landing's azimuth varies by up to this either way from its launch's,
// the launch angle by up to this many degrees.
ARRIVAL_DEBRIS_AZIMUTH_JITTER :: 0.075
ARRIVAL_DEBRIS_ANGLE_JITTER_DEGREES :: 3.0
// The share of the launch below which a piece is stone (dug from under
// the topsoil).
ARRIVAL_DEBRIS_STONE_SHARE :: 0.3
ARRIVAL_BANG_SOUND :: "arrival_bang"
ARRIVAL_PATTER_SOUNDS :: [3]string{"arrival_patter_1", "arrival_patter_2", "arrival_patter_3"}

// The hashed keys of a piece's values.
Arrival_Debris_Key :: enum u64 {
	Share,
	Azimuth,
	Spread,
	Landing_Azimuth,
	Angle,
	Edge,
	Brightness,
	Spin_Height,
	Spin_Turn,
	Spin_Rate,
	Sounds,
	Patter,
	Pitch,
	Rest,
}

// Where the debris flies from, in metres: the generation baked with its
// crater, the crater's home on the sphere with the planet's up there and
// its tangents, the crater's crest and floor radii, the pod's clearance
// from the home (its base centre's distance on the tangent plane plus
// its reach), the launch angle, the pieces and their resting seconds.
Arrival_Debris_Site :: struct {
	generation:                                 Planet_Generation,
	home, up, east, north:                      [3]f32,
	radius_metres, floor_radius_metres:         f32,
	clear_metres, angle_radians:                f32,
	pieces:                                     int,
	rest_seconds:                               f32,
}

// One piece: its launch and landing on the ground, the unit along its
// flight on the tangent plane, the site's up, its spin; the seconds
// after the hit it leaves, its flight's seconds, the tangent distance it
// covers, its vertical speed at the launch, its edge and brightness, the
// seconds after the hit it starts to sink; stone or topsoil, whether its
// landing sounds and which patter.
Arrival_Debris_Piece :: struct {
	launch, landing, along, up, spin_axis: [3]f32,
	launch_seconds, flight_seconds:        f32,
	reach_metres, vertical_speed:          f32,
	spin_radians_per_second:               f32,
	edge_metres, brightness, fade_seconds: f32,
	stone, sounds:                         bool,
	patter:                                int,
}

// The site of the generation's crater, the pod's base centre and reach
// in metres. found is false without a crater; with pieces 0 the site
// is found, so the dust and the bang stay and only the clods go.
arrival_debris_site :: proc(generation: Planet_Generation, config: Game_Config, pod_base: [3]f32, pod_reach_metres: f32) -> (site: Arrival_Debris_Site, found: bool) {
	crater := generation.crater
	if crater.reach == 0 {
		return {}, false
	}
	home_unit, _ := normalize_fixed(crater.home)
	site.generation = baked_planet_generation(generation)
	site.home = world_position_to_metres(World_Position(crater.home))
	site.up = unit_vector_to_f32(home_unit)
	site.north = unit_vector_to_f32(frame_north_tangent(home_unit))
	site.east = linalg.cross(site.north, site.up)
	site.radius_metres = f32(f64(crater.radius) / POSITION_UNITS_PER_METRE)
	site.floor_radius_metres = f32(f64(crater.floor_radius) / POSITION_UNITS_PER_METRE)
	site.clear_metres = arrival_tangent_distance(pod_base - site.home, site.up) + pod_reach_metres
	site.angle_radians = math.to_radians(f32(config.arrival_debris_angle_degrees))
	site.pieces = clamp(config.arrival_debris_pieces, 0, MAXIMUM_ARRIVAL_DEBRIS_PIECES)
	site.rest_seconds = f32(config.arrival_debris_rest_seconds)
	return site, true
}

// The length of an offset laid on the tangent plane of up.
arrival_tangent_distance :: proc(offset, up: [3]f32) -> f32 {
	return linalg.length(offset - up * linalg.dot(offset, up))
}

// The baked generation's surface on the radial through the point
// distance_metres from the home along the azimuth (from the east towards
// the north) on the tangent plane.
arrival_debris_ground :: proc(site: Arrival_Debris_Site, azimuth, distance_metres: f32) -> [3]f32 {
	point := site.home + (site.east * math.cos(azimuth) + site.north * math.sin(azimuth)) * distance_metres
	position := World_Position{i64(math.round(f64(point.x) * POSITION_UNITS_PER_METRE)), i64(math.round(f64(point.y) * POSITION_UNITS_PER_METRE)), i64(math.round(f64(point.z) * POSITION_UNITS_PER_METRE))}
	return world_position_to_metres(field_surface_under(site.generation, position, 0))
}

// The pod's reach: a sphere about its base centre holding the hull and a
// cell round it in any pose, in metres.
arrival_pod_reach_metres :: proc(machine: Machine, frame: Frame) -> f32 {
	half_width := f32(machine.footprint.x) / 2 + 1
	half_depth := f32(machine.footprint.z) / 2 + 1
	height := f32(machine.footprint.y) + 1
	pitch_metres := f32(f64(frame.pitch_millimetres) / MILLIMETRES_PER_METRE)
	return math.sqrt(half_width * half_width + half_depth * half_depth + height * height) * pitch_metres
}

// A piece's launch and landing distances from the home by its launch
// share (0 inner to 1 outer) and a hashed spread: the launch out from
// the floor (or the pod's clearance) towards the crest, the landing by
// the ejecta blanket's cube law between the rim (or past the clearance)
// and five radii, the inner pieces farthest.
arrival_debris_distances :: proc(site: Arrival_Debris_Site, share, spread: f32) -> (launch_metres, landing_metres: f32) {
	launch_least := max(site.floor_radius_metres, site.clear_metres)
	launch_most := max(0.85 * site.radius_metres, launch_least + 0.5)
	launch_metres = launch_least + (launch_most - launch_least) * share
	landing_least := max(site.radius_metres, site.clear_metres + 1)
	landing_most := max(5 * site.radius_metres, landing_least)
	blanket := clamp(1 - share + 0.1 * (spread - 0.5), 0, 1)
	landing_metres = landing_least / (1 - (1 - landing_least / landing_most) * blanket)
	return
}

// The parabola from launch to landing leaving at angle above the tangent
// plane, gravity along up: the unit along the tangent plane, the tangent
// distance, the vertical speed and the seconds of the flight. Steeper
// only where the landing lies so high that the angle cannot reach it.
arrival_debris_arc :: proc(launch, landing, up: [3]f32, angle: f32) -> (along: [3]f32, reach_metres, vertical_speed, flight_seconds: f32) {
	offset := landing - launch
	rise := linalg.dot(offset, up)
	level := offset - up * rise
	reach_metres = linalg.length(level)
	along = reach_metres > 0 ? level / reach_metres : [3]f32{}
	slope := reach_metres * math.tan(angle)
	lift := max(slope - rise, 0.25 * slope)
	gravity := f32(ARRIVAL_GRAVITY_METRES_PER_SECOND_SQUARED)
	flight_seconds = max(math.sqrt(2 * lift / gravity), 0.01)
	vertical_speed = rise / flight_seconds + gravity * flight_seconds / 2
	return
}

// A hashed unit vector from two fractions.
arrival_debris_spin_axis :: proc(height, turn: f32) -> [3]f32 {
	z := 2 * height - 1
	ring := math.sqrt(max(1 - z * z, 0))
	return {ring * math.cos(turn * math.TAU), ring * math.sin(turn * math.TAU), z}
}

arrival_debris_hash :: proc(index: int, salt: u64) -> u64 {
	return generation_seed.hash_combine(generation_seed.hash_combine(salt, ARRIVAL_DEBRIS_SALT), u64(index))
}

arrival_debris_fraction :: proc(hash: u64, key: Arrival_Debris_Key) -> f32 {
	return arrival_puff_fraction(hash, u64(key))
}

// Piece index of the site (doc/presentation.md, The arrival, The debris).
arrival_debris_piece :: proc(site: Arrival_Debris_Site, index: int, salt: u64) -> Arrival_Debris_Piece {
	hash := arrival_debris_hash(index, salt)
	share := arrival_debris_fraction(hash, .Share)
	azimuth := arrival_debris_fraction(hash, .Azimuth) * math.TAU
	launch_metres, landing_metres := arrival_debris_distances(site, share, arrival_debris_fraction(hash, .Spread))
	piece := Arrival_Debris_Piece {
		launch         = arrival_debris_ground(site, azimuth, launch_metres),
		landing        = arrival_debris_ground(site, azimuth + ARRIVAL_DEBRIS_AZIMUTH_JITTER * (2 * arrival_debris_fraction(hash, .Landing_Azimuth) - 1), landing_metres),
		up             = site.up,
		spin_axis      = arrival_debris_spin_axis(arrival_debris_fraction(hash, .Spin_Height), arrival_debris_fraction(hash, .Spin_Turn)),
		launch_seconds = ARRIVAL_DEBRIS_LAUNCH_SPREAD_SECONDS * share,
		spin_radians_per_second = 3 + 9 * arrival_debris_fraction(hash, .Spin_Rate),
		brightness     = 0.85 + 0.25 * arrival_debris_fraction(hash, .Brightness),
		stone          = share < ARRIVAL_DEBRIS_STONE_SHARE,
		sounds         = arrival_debris_fraction(hash, .Sounds) < ARRIVAL_PATTER_SHARE,
		patter         = min(int(arrival_debris_fraction(hash, .Patter) * 3), 2),
	}
	edge_share := arrival_debris_fraction(hash, .Edge)
	piece.edge_metres = ARRIVAL_DEBRIS_SMALLEST_METRES + (ARRIVAL_DEBRIS_LARGEST_METRES - ARRIVAL_DEBRIS_SMALLEST_METRES) * edge_share * edge_share
	angle := site.angle_radians + math.to_radians(f32(ARRIVAL_DEBRIS_ANGLE_JITTER_DEGREES)) * (2 * arrival_debris_fraction(hash, .Angle) - 1)
	piece.along, piece.reach_metres, piece.vertical_speed, piece.flight_seconds = arrival_debris_arc(piece.launch, piece.landing, site.up, angle)
	piece.fade_seconds = piece.launch_seconds + piece.flight_seconds + site.rest_seconds * (0.7 + 0.3 * arrival_debris_fraction(hash, .Rest))
	return piece
}

// The piece at seconds after the hit: its centre, its turn and its edge;
// hidden before its launch and once it has sunk. In flight on its
// parabola, its bottom on the arc, tumbling; at rest on its landing with
// the tumble it landed with, sunk a quarter of its edge, then sinking
// below the ground over ARRIVAL_DEBRIS_FADE_SECONDS.
arrival_debris_pose :: proc(piece: Arrival_Debris_Piece, seconds_since_hit: f32) -> (centre: [3]f32, turn: matrix[3, 3]f32, edge_metres: f32, visible: bool) {
	edge_metres = piece.edge_metres
	flight := seconds_since_hit - piece.launch_seconds
	if flight < 0 || seconds_since_hit >= piece.fade_seconds + ARRIVAL_DEBRIS_FADE_SECONDS {
		return {}, 1, edge_metres, false
	}
	if flight <= piece.flight_seconds {
		return arrival_debris_flight_point(piece, flight), linalg.matrix3_rotate_f32(piece.spin_radians_per_second * flight, piece.spin_axis), edge_metres, true
	}
	sink := clamp((seconds_since_hit - piece.fade_seconds) / ARRIVAL_DEBRIS_FADE_SECONDS, 0, 1)
	centre = piece.landing + piece.up * (edge_metres * (0.25 - 1.25 * sink))
	return centre, linalg.matrix3_rotate_f32(piece.spin_radians_per_second * piece.flight_seconds, piece.spin_axis), edge_metres, true
}

// The piece's centre at flight seconds after its launch on its
// parabola, its bottom on the arc.
arrival_debris_flight_point :: proc(piece: Arrival_Debris_Piece, flight: f32) -> [3]f32 {
	gravity := f32(ARRIVAL_GRAVITY_METRES_PER_SECOND_SQUARED)
	height := piece.vertical_speed * flight - gravity * flight * flight / 2
	return piece.launch + piece.along * (piece.reach_metres * flight / piece.flight_seconds) + piece.up * (height + piece.edge_metres / 2)
}

// The six faces of a box, each with its outward normal and its corners
// counter-clockwise seen from outside.
arrival_debris_box_faces :: proc(centre: [3]f32, turn: matrix[3, 3]f32, edge_metres: f32) -> (normals: [6][3]f32, corners: [6][4][3]f32) {
	half := edge_metres / 2
	axes := [3][3]f32{turn[0] * half, turn[1] * half, turn[2] * half}
	// Each face's normal axis and sign, and the two axes whose cross is
	// the outward normal.
	faces := [6][3]int{{0, 1, 2}, {0, 2, 1}, {1, 2, 0}, {1, 0, 2}, {2, 0, 1}, {2, 1, 0}}
	for face, index in faces {
		sign: f32 = index % 2 == 0 ? 1 : -1
		normal := axes[face[0]] * sign
		first, second := axes[face[1]], axes[face[2]]
		middle := centre + normal
		normals[index] = linalg.normalize(normal)
		corners[index] = {middle - first - second, middle + first - second, middle + first + second, middle - first + second}
	}
	return
}

// A colour scaled by a factor, clamped.
arrival_scaled_color :: proc(color: rl.Color, factor: f32) -> rl.Color {
	scale :: proc(channel: u8, factor: f32) -> u8 {
		return u8(clamp(f32(channel) * factor, 0, 255))
	}
	return {scale(color.r, factor), scale(color.g, factor), scale(color.b, factor), color.a}
}

// Topsoil's and stone's colours at the site: each material tile's mean
// texel times the palette's tint at the home times the field shader's
// tint_scale.
arrival_debris_colors :: proc(renderer: ^Field_Renderer, palette: [][3]int, site: Arrival_Debris_Site) -> (colors: [2]rl.Color) {
	tint := palette[planet_tint(site.generation, World_Position(site.generation.crater.home))]
	tint_share := [3]f32{f32(tint.r), f32(tint.g), f32(tint.b)} / 255 * ARRIVAL_DEBRIS_TINT_SCALE
	for material, slot in ([2]Field_Material{.Topsoil, .Stone}) {
		mean := renderer.material_colors[field_material_tile(material)] * tint_share
		colors[slot] = {u8(clamp(mean.r, 0, 1) * 255), u8(clamp(mean.g, 0, 1) * 255), u8(clamp(mean.b, 0, 1) * 255), 255}
	}
	return
}

// Inside BeginMode3D while Settled: one quad batch of six shaded faces
// per visible piece, depth written; colors are topsoil's and stone's,
// light the scene's day factor. Each face is lit by its slope to the up.
draw_arrival_debris :: proc(site: Arrival_Debris_Site, view: Arrival_View, salt: u64, colors: [2]rl.Color, light: f32) {
	if view.phase != .Settled {
		return
	}
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.QUADS)
	for index in 0 ..< min(site.pieces, MAXIMUM_ARRIVAL_DEBRIS_PIECES) {
		piece := arrival_debris_piece(site, index, salt)
		centre, turn, edge, visible := arrival_debris_pose(piece, view.seconds_since_hit)
		if !visible {
			continue
		}
		color := colors[piece.stone ? 1 : 0]
		normals, corners := arrival_debris_box_faces(centre, turn, edge)
		for face in 0 ..< 6 {
			shaded := arrival_scaled_color(color, light * piece.brightness * (0.5 + 0.5 * max(linalg.dot(normals[face], site.up), 0)))
			rlgl.Color4ub(shaded.r, shaded.g, shaded.b, 255)
			for corner in corners[face] {
				rlgl.Vertex3f(corner.x, corner.y, corner.z)
			}
		}
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// Piece index's landing sound: its patter, its volume by its edge, its
// pitch hashed, the seconds after the hit it lands and whether it sounds.
arrival_patter :: proc(site: Arrival_Debris_Site, index: int, salt: u64) -> (id: string, volume, pitch: f32, landing_seconds: f32, sounds: bool) {
	piece := arrival_debris_piece(site, index, salt)
	edge_share := (piece.edge_metres - ARRIVAL_DEBRIS_SMALLEST_METRES) / (ARRIVAL_DEBRIS_LARGEST_METRES - ARRIVAL_DEBRIS_SMALLEST_METRES)
	patters := ARRIVAL_PATTER_SOUNDS
	pitch = 0.8 + 0.4 * arrival_debris_fraction(arrival_debris_hash(index, salt), .Pitch)
	return patters[piece.patter], 0.35 + 0.65 * edge_share, pitch, piece.launch_seconds + piece.flight_seconds, piece.sounds
}

// Every sounding piece whose landing lies after from_seconds and at or
// before to_seconds. The mixer's 40 ms gap drops a collision, so the
// patter thins in its densest second.
play_arrival_patter :: proc(mixer: ^Audio_Mixer, site: Arrival_Debris_Site, from_seconds, to_seconds: f32, salt: u64) {
	if to_seconds <= from_seconds {
		return
	}
	for index in 0 ..< min(site.pieces, MAXIMUM_ARRIVAL_DEBRIS_PIECES) {
		id, volume, pitch, landing, sounds := arrival_patter(site, index, salt)
		if sounds && landing > from_seconds && landing <= to_seconds {
			play_effect(mixer, id, volume, pitch)
		}
	}
}
