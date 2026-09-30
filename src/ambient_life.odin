package game

import "core:math"
import "core:math/linalg"
import "generation_seed"

// Ambient life (work item 0075): bird flocks over forests and plains,
// insect motes around flowers and fish shadows under water. Render only
// and stateless like the weather: every position is a pure function of
// the world seed, a cell, the tick or the render time, so nothing is
// saved and the simulation never reads any of it. The pure parts live
// here, the drawing in render_life.odin.
//
// No perceivable repetition (DESIGN.md): every flock, bird, mote and fish
// takes its phase, its period and its path's shape from a hash of its
// cell, so no two share a cadence.

// Flocks sit on a world aligned grid of cells this many blocks wide.
FLOCK_CELL_SIZE :: 96
FLOCK_SEED_SALT :: u64(0x5b1d_f10c_ca7e_0075)
FLOCK_MINIMUM_BIRDS :: 5
FLOCK_MAXIMUM_BIRDS :: 9
// A flock's loop: a rounded rectangle this long and wide, in blocks.
FLOCK_LOOP_LENGTH :: 40.0
FLOCK_LOOP_WIDTH :: 24.0
FLOCK_LOOP_CORNER_RADIUS :: 8.0
// Above the surface at the loop's centre, in blocks.
FLOCK_MINIMUM_ALTITUDE :: 18
FLOCK_MAXIMUM_ALTITUDE :: 26
FLOCK_PERIOD_SECONDS :: 60.0
// A flock's period lies within this share either side of
// FLOCK_PERIOD_SECONDS.
FLOCK_PERIOD_SPREAD :: 0.1
// The loop's centre lies up to this many blocks from the cell's centre
// along x and z, so the flocks do not line up with the grid.
FLOCK_CENTRE_JITTER :: 20
// How far a bird can be from its loop's centre horizontally: half the
// loop's diagonal and the side spread.
FLOCK_REACH :: 26.0
// Birds trail each other this share of the loop apart, give or take
// half of it from a hash.
BIRD_SPACING_SHARE :: 0.01
// A bird flies up to this many blocks to either side of the loop.
BIRD_SIDE_SPREAD :: 2.0
BIRD_BOB_AMPLITUDE :: 0.8
BIRD_BOB_MINIMUM_SECONDS :: 4.0
BIRD_BOB_MAXIMUM_SECONDS :: 7.0
// Wing beats per second, and the period over which a bird switches
// between flapping and gliding.
BIRD_FLAP_MINIMUM_HERTZ :: 2.4
BIRD_FLAP_MAXIMUM_HERTZ :: 3.6
BIRD_GLIDE_MINIMUM_SECONDS :: 5.0
BIRD_GLIDE_MAXIMUM_SECONDS :: 11.0
// The wing tips' lift while gliding, in -1 to 1.
BIRD_GLIDE_LIFT :: 0.15
BIRD_DRAW_DISTANCE :: 160.0

INSECT_SEED_SALT :: u64(0x1b5e_c7a5_0075_0001)
// One flower in this many has insects.
INSECT_FLOWER_SHARE :: 2
INSECT_MOTES_PER_FLOWER :: 2
// Motes circle this far above the flower's cell floor, within a radius
// of the minimum to the maximum.
INSECT_HEIGHT :: 0.7
INSECT_MINIMUM_RADIUS :: 0.3
INSECT_MAXIMUM_RADIUS :: 0.6
INSECT_VERTICAL_AMPLITUDE :: 0.25
// Angular speeds of the Lissajous path along x, z and y in radians per
// second, each from its minimum to its maximum by a hash.
INSECT_SPEED_MINIMUM :: [3]f32{1.6, 1.9, 0.7}
INSECT_SPEED_MAXIMUM :: [3]f32{2.8, 3.1, 1.3}
INSECT_DRAW_DISTANCE :: 24.0

FISH_SEED_SALT :: u64(0xf1_5bad_0075_0002)
// One water surface cell in this many holds a fish shadow.
FISH_CELL_SHARE :: 8
// Below the top of a source water cell.
FISH_DEPTH :: 0.2
FISH_LENGTH :: 0.5
FISH_WIDTH :: 0.18
FISH_MINIMUM_PERIOD_SECONDS :: 16.0
FISH_MAXIMUM_PERIOD_SECONDS :: 26.0
// The figure of eight's half length in blocks.
FISH_MINIMUM_AMPLITUDE :: 1.0
FISH_MAXIMUM_AMPLITUDE :: 1.6
FISH_DRAW_DISTANCE :: 32.0

// Life shows fully above the second daylight blend and not at all below
// the first; rain above this intensity grounds it.
LIFE_DAYLIGHT_START :: 0.2
LIFE_DAYLIGHT_FULL :: 0.6
LIFE_RAIN_GROUNDED :: 0.25

// One flock: centre is the loop's centre at flying height, angle the
// loop's turn about y, direction 1 or -1 the way round it.
Flock :: struct {
	hash:           u64,
	centre:         [3]f32,
	angle:          f32,
	bird_count:     int,
	period_seconds: f64,
	phase:          f64,
	direction:      f64,
}

// Where a bird is and the unit horizontal direction it flies in.
Bird_Pose :: struct {
	position: [3]f32,
	heading:  [3]f32,
}

// heading is the unit direction in x and z the fish swims in.
Fish_Pose :: struct {
	position: [3]f32,
	heading:  [2]f32,
}

// 0 to 1 from a stream of the hash.
hash_share :: proc(hash: u64, stream: u64) -> f64 {
	return generation_seed.hash_to_unit(generation_seed.hash_combine(hash, stream))
}

hash_lerp :: proc(hash: u64, stream: u64, minimum, maximum: f64) -> f64 {
	return minimum + (maximum - minimum) * hash_share(hash, stream)
}

flock_cell_hash :: proc(seed: u64, cell: [2]i32) -> u64 {
	return generation_seed.hash_column(seed ~ FLOCK_SEED_SALT, cell.x, cell.y)
}

// density is the bird_density of the biome at the loop's centre.
flock_present :: proc(hash: u64, density: f32) -> bool {
	return generation_seed.hash_to_unit(hash) < f64(density)
}

// The column the loop circles, whose surface and biome place the flock.
flock_centre_column :: proc(cell: [2]i32, hash: u64) -> [2]i32 {
	jitter := [2]i32 {
		i32(generation_seed.hash_to_range(generation_seed.hash_combine(hash, 1), -FLOCK_CENTRE_JITTER, FLOCK_CENTRE_JITTER)),
		i32(generation_seed.hash_to_range(generation_seed.hash_combine(hash, 2), -FLOCK_CENTRE_JITTER, FLOCK_CENTRE_JITTER)),
	}
	return cell * FLOCK_CELL_SIZE + FLOCK_CELL_SIZE / 2 + jitter
}

make_flock :: proc(hash: u64, column: [2]i32, surface_height: i32) -> Flock {
	altitude := generation_seed.hash_to_range(generation_seed.hash_combine(hash, 3), FLOCK_MINIMUM_ALTITUDE, FLOCK_MAXIMUM_ALTITUDE)
	return Flock {
		hash = hash,
		centre = {f32(column.x) + 0.5, f32(surface_height) + f32(altitude), f32(column.y) + 0.5},
		angle = f32(hash_share(hash, 4) * math.TAU),
		bird_count = int(generation_seed.hash_to_range(generation_seed.hash_combine(hash, 5), FLOCK_MINIMUM_BIRDS, FLOCK_MAXIMUM_BIRDS)),
		period_seconds = FLOCK_PERIOD_SECONDS * hash_lerp(hash, 6, 1 - FLOCK_PERIOD_SPREAD, 1 + FLOCK_PERIOD_SPREAD),
		phase = hash_share(hash, 7),
		direction = hash_share(hash, 8) < 0.5 ? -1 : 1,
	}
}

// The flock cells whose loops can come within distance of position (x
// and z), inclusive.
flock_cells_around :: proc(position: [2]f32, distance: f32) -> (minimum, maximum: [2]i32) {
	reach := distance + FLOCK_REACH + FLOCK_CENTRE_JITTER + FLOCK_CELL_SIZE / 2
	for axis in 0 ..< 2 {
		minimum[axis] = i32(math.floor((position[axis] - reach) / FLOCK_CELL_SIZE))
		maximum[axis] = i32(math.floor((position[axis] + reach) / FLOCK_CELL_SIZE))
	}
	return
}

rounded_rectangle_perimeter :: proc() -> f32 {
	straight: f32 = 2 * (FLOCK_LOOP_LENGTH - 2 * FLOCK_LOOP_CORNER_RADIUS) + 2 * (FLOCK_LOOP_WIDTH - 2 * FLOCK_LOOP_CORNER_RADIUS)
	return straight + f32(math.TAU * FLOCK_LOOP_CORNER_RADIUS)
}

// The centres of the four corner arcs, in the order the loop reaches
// them after each side.
@(rodata)
rounded_rectangle_corner_signs := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}

// A point on the loop in its own plane (x along its length, y along its
// width), share 0 to 1 of the way round by arc length, counter clockwise
// from the start of the side at -y. Point symmetric: share + 0.5 is the
// point through the centre.
rounded_rectangle_point :: proc(share: f64) -> [2]f32 {
	radius: f32 = FLOCK_LOOP_CORNER_RADIUS
	inner := [2]f32{FLOCK_LOOP_LENGTH / 2 - radius, FLOCK_LOOP_WIDTH / 2 - radius}
	quarter_arc := radius * math.PI / 2
	distance := f32(share - math.floor(share)) * rounded_rectangle_perimeter()
	for side in 0 ..< 4 {
		along := side_direction(side)
		outward := [2]f32{along.y, -along.x}
		length := 2 * inner[side % 2]
		if distance < length {
			return inner * rounded_rectangle_corner_signs[side] + outward * radius + along * distance
		}
		distance -= length
		if distance < quarter_arc || side == 3 {
			angle := min(distance / radius, math.PI / 2)
			centre := inner * rounded_rectangle_corner_signs[(side + 1) % 4]
			return centre + radius * (outward * math.cos(angle) + along * math.sin(angle))
		}
		distance -= quarter_arc
	}
	return {}
}

// The direction of the loop's side, counter clockwise: +x, +y, -x, -y.
side_direction :: proc(side: int) -> [2]f32 {
	directions := [4][2]f32{{1, 0}, {0, 1}, {-1, 0}, {0, -1}}
	return directions[side]
}

rotate_2d :: proc(point: [2]f32, angle: f32) -> [2]f32 {
	cosine, sine := math.cos(angle), math.sin(angle)
	return {point.x * cosine - point.y * sine, point.x * sine + point.y * cosine}
}

// Share of the loop a bird is at: the flock's phase moved on by the loop
// time, the birds behind the first spaced by a hash.
flock_bird_share :: proc(flock: Flock, bird: int, loop_seconds: f64) -> f64 {
	bird_hash := generation_seed.hash_combine(flock.hash, 100 + u64(bird))
	behind := (f64(bird) + 0.5 * hash_share(bird_hash, 1)) * BIRD_SPACING_SHARE
	share := flock.phase + flock.direction * (loop_seconds / flock.period_seconds - behind)
	return share - math.floor(share)
}

// loop_seconds is the tick in seconds, so the flock's path follows the
// simulation's clock: a flock is where it is at a tick on every run.
flock_bird_pose :: proc(flock: Flock, bird: int, loop_seconds: f64) -> Bird_Pose {
	bird_hash := generation_seed.hash_combine(flock.hash, 100 + u64(bird))
	share := flock_bird_share(flock, bird, loop_seconds)
	point := rounded_rectangle_point(share)
	ahead := rounded_rectangle_point(share + flock.direction * 0.001) - point
	tangent := linalg.normalize0(ahead)
	side := [2]f32{tangent.y, -tangent.x} * f32(hash_lerp(bird_hash, 2, -BIRD_SIDE_SPREAD, BIRD_SIDE_SPREAD))
	local := rotate_2d(point + side, flock.angle)
	heading := rotate_2d(tangent, flock.angle)
	bob_period := hash_lerp(bird_hash, 3, BIRD_BOB_MINIMUM_SECONDS, BIRD_BOB_MAXIMUM_SECONDS)
	bob := BIRD_BOB_AMPLITUDE * math.sin(loop_seconds / bob_period * math.TAU + hash_share(bird_hash, 4) * math.TAU)
	return Bird_Pose {
		position = flock.centre + {local.x, f32(bob), local.y},
		heading = {heading.x, 0, heading.y},
	}
}

// The wing tips' lift, -1 to 1, at the render time: a wing beat of the
// bird's own speed, faded in and out by a slow wave of its own period so
// the bird alternates flapping and gliding.
bird_wing_lift :: proc(flock_hash: u64, bird: int, seconds: f64) -> f32 {
	bird_hash := generation_seed.hash_combine(flock_hash, 100 + u64(bird))
	hertz := hash_lerp(bird_hash, 5, BIRD_FLAP_MINIMUM_HERTZ, BIRD_FLAP_MAXIMUM_HERTZ)
	flap := math.sin(seconds * hertz * math.TAU + hash_share(bird_hash, 6) * math.TAU)
	glide_period := hash_lerp(bird_hash, 7, BIRD_GLIDE_MINIMUM_SECONDS, BIRD_GLIDE_MAXIMUM_SECONDS)
	wave := math.sin(seconds / glide_period * math.TAU + hash_share(bird_hash, 8) * math.TAU)
	flapping := smoothstep(-0.3, 0.3, wave)
	return f32(BIRD_GLIDE_LIFT + (flap - BIRD_GLIDE_LIFT) * flapping)
}

life_cell_hash :: proc(cell: World_Coordinate, salt: u64) -> u64 {
	return generation_seed.hash_combine(salt, u64(u32(cell.x)) ~ (u64(u32(cell.y)) << 21) ~ (u64(u32(cell.z)) << 42))
}

// Whether a flower's cell has insects circling it.
flower_has_insects :: proc(cell: World_Coordinate) -> bool {
	return life_cell_hash(cell, INSECT_SEED_SALT) % INSECT_FLOWER_SHARE == 0
}

// A mote's Lissajous path around the flower at the render time: its
// radius, its three angular speeds and phases from a hash of the cell and
// the mote.
insect_mote_position :: proc(cell: World_Coordinate, mote: int, seconds: f64) -> [3]f32 {
	hash := generation_seed.hash_combine(life_cell_hash(cell, INSECT_SEED_SALT), u64(mote) + 1)
	radius := hash_lerp(hash, 1, INSECT_MINIMUM_RADIUS, INSECT_MAXIMUM_RADIUS)
	minimum, maximum := INSECT_SPEED_MINIMUM, INSECT_SPEED_MAXIMUM
	angles: [3]f64
	for axis in 0 ..< 3 {
		speed := hash_lerp(hash, 2 + u64(axis), f64(minimum[axis]), f64(maximum[axis]))
		angles[axis] = seconds * speed + hash_share(hash, 5 + u64(axis)) * math.TAU
	}
	offset := [3]f64{radius * math.sin(angles.x), INSECT_HEIGHT + INSECT_VERTICAL_AMPLITUDE * math.sin(angles.z), radius * math.sin(angles.y)}
	return {f32(cell.x) + 0.5 + f32(offset.x), f32(cell.y) + f32(offset.y), f32(cell.z) + 0.5 + f32(offset.z)}
}

// Whether a water surface cell holds a fish shadow.
fish_in_cell :: proc(cell: World_Coordinate) -> bool {
	return life_cell_hash(cell, FISH_SEED_SALT) % FISH_CELL_SHARE == 0
}

// A slow figure of eight (a lemniscate of Gerono) around the cell's
// centre at the render time, just under the surface; its period, size,
// turn and way round from a hash of the cell.
fish_pose :: proc(cell: World_Coordinate, seconds: f64) -> Fish_Pose {
	hash := life_cell_hash(cell, FISH_SEED_SALT)
	period := hash_lerp(hash, 1, FISH_MINIMUM_PERIOD_SECONDS, FISH_MAXIMUM_PERIOD_SECONDS)
	amplitude := f32(hash_lerp(hash, 2, FISH_MINIMUM_AMPLITUDE, FISH_MAXIMUM_AMPLITUDE))
	turn := f32(hash_share(hash, 3) * math.TAU)
	direction: f64 = hash_share(hash, 4) < 0.5 ? -1 : 1
	angle := direction * seconds / period * math.TAU + hash_share(hash, 5) * math.TAU
	sine, cosine := f32(math.sin(angle)), f32(math.cos(angle))
	point := rotate_2d(amplitude * [2]f32{sine, sine * cosine}, turn)
	velocity := rotate_2d(f32(direction) * [2]f32{cosine, cosine * cosine - sine * sine}, turn)
	return Fish_Pose {
		position = {f32(cell.x) + 0.5 + point.x, f32(cell.y) + 1 - FISH_DEPTH, f32(cell.z) + 0.5 + point.y},
		heading = linalg.normalize0(velocity),
	}
}

// How much life shows, 0 to 1: by day and not in rain. rain_intensity is
// 0 unless it rains.
life_presence :: proc(daylight_blend, rain_intensity: f32) -> f32 {
	day := smoothstep(LIFE_DAYLIGHT_START, LIFE_DAYLIGHT_FULL, f64(daylight_blend))
	dry := 1 - smoothstep(0, LIFE_RAIN_GROUNDED, f64(rain_intensity))
	return f32(day * dry)
}

// 1 before the fog starts, 0 where it is complete.
fog_fade :: proc(distance, fog_start, fog_end: f32) -> f32 {
	return f32(1 - smoothstep(f64(fog_start), f64(fog_end), f64(distance)))
}

// Squared distance from a point to a chunk's box, 0 inside it.
chunk_distance_squared :: proc(position: [3]f32, coordinate: Chunk_Coordinate) -> f32 {
	origin := chunk_origin(coordinate)
	minimum := [3]f32{f32(origin.x), f32(origin.y), f32(origin.z)}
	nearest := linalg.clamp(position, minimum, minimum + CHUNK_SIZE)
	return linalg.length2(position - nearest)
}
