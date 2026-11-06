package game

import "core:math"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "generation_seed"

// The flakes the heat shield sheds during the heating (work items 0290
// and 0304, doc/presentation.md, The arrival): each leaves the shield's
// rim with the pod's velocity and a hashed sideways nudge and loses its
// speed against the air exponentially, so relative to the pod it drifts
// aft through the wake past the portholes, a charred plate with a gold
// rim and a plasma streak against the air, drawn after the wake for
// every viewer. Its path is a closed form in the pod's model frame
// (cells, the air streaming along +y), and every value is a pure
// function of its index, the seed and the arrival's seconds, so a
// joiner or a load sees the same flakes. Nothing here is simulation
// state.

ARRIVAL_FLAKE_SALT :: 0x666c616b
// The births' time slots and the candidates each slot holds.
ARRIVAL_FLAKE_SLOT_SECONDS :: 0.05
ARRIVAL_FLAKE_CANDIDATES_PER_SLOT :: 8
// A flake's life, hashed between these.
ARRIVAL_FLAKE_SHORTEST_LIFE_SECONDS :: 1.6
ARRIVAL_FLAKE_LONGEST_LIFE_SECONDS :: 2.0
// The slots a frame scans back from the current one: the longest life.
ARRIVAL_FLAKE_SLOTS_BACK :: 40
// The most flakes a frame evaluates, alive or drawn: the cap.
MAXIMUM_ARRIVAL_FLAKES :: (ARRIVAL_FLAKE_SLOTS_BACK + 1) * ARRIVAL_FLAKE_CANDIDATES_PER_SLOT
// The air's speed past the pod as the flakes feel it, cells a second.
ARRIVAL_FLAKE_AIR_CELLS_PER_SECOND :: 7.0
// A flake's drag time, hashed between these.
ARRIVAL_FLAKE_SHORTEST_DRAG_SECONDS :: 0.8
ARRIVAL_FLAKE_LONGEST_DRAG_SECONDS :: 1.25
// The nudge's outward part, hashed between these, cells a second.
ARRIVAL_FLAKE_SLOWEST_OUTWARD :: 0.4
ARRIVAL_FLAKE_FASTEST_OUTWARD :: 1.6
// The nudge's sideways part, at most this either way, cells a second.
ARRIVAL_FLAKE_SIDEWAYS :: 0.8
// The plate's half size, smallest + (largest - smallest) times a hashed
// share squared, so most are small: 8 to 15 px at 720p from the chair
// (0304).
ARRIVAL_FLAKE_SMALLEST_CELLS :: 0.055
ARRIVAL_FLAKE_LARGEST_CELLS :: 0.11
// The streak's length: these seconds of the speed against the air, 4.6
// cells at the birth (0304).
ARRIVAL_FLAKE_STREAK_SECONDS :: 0.65
// The fade in after the birth and out before the end.
ARRIVAL_FLAKE_FADE_SECONDS :: 0.15
// The vertex colour's brightness scale, flake_brightest in
// arrival_flake.vs.
ARRIVAL_FLAKE_BRIGHTEST :: 2.0
ARRIVAL_FLAKE_VERTEX_SHADER_PATH :: "shaders/arrival_flake.vs"
ARRIVAL_FLAKE_FRAGMENT_SHADER_PATH :: "shaders/arrival_flake.fs"

#assert(MAXIMUM_ARRIVAL_FLAKES_PER_SECOND * ARRIVAL_FLAKE_SLOT_SECONDS <= ARRIVAL_FLAKE_CANDIDATES_PER_SLOT)

// The hashed keys of a flake's values.
Arrival_Flake_Key :: enum u64 {
	Birth,
	Exists,
	Life,
	Azimuth,
	Height,
	Drag,
	Outward,
	Sideways,
	Size,
	Brightness,
}

// What the flakes are drawn from: the entry's curve, the descent's
// length in seconds, the births a second at heat 1, the heat shield's
// rim (its radius and height in cells of the model's frame) and the
// world's salt.
Arrival_Flake_Source :: struct {
	curve:                                                        ^Arrival_Curve,
	descent_seconds, flakes_per_second, shield_radius, rim_height: f32,
	salt:                                                         u64,
}

// One flake: its plate's centre in cells of the model's frame, the
// streak's unit direction there, its length and the plate's half size in
// cells, its brightness, flicker and whiteness, its plate's opacity
// (the fade: every flake is a charred plate, 0304) and whether it lives.
Arrival_Flake :: struct {
	position, streak:                                                    [3]f32,
	streak_cells, size_cells, brightness, flicker, whiteness, dark_core: f32,
	alive:                                                               bool,
}

arrival_flake_hash :: proc(index: int, salt: u64) -> u64 {
	return generation_seed.hash_combine(generation_seed.hash_combine(salt, ARRIVAL_FLAKE_SALT), u64(index))
}

arrival_flake_fraction :: proc(hash: u64, key: Arrival_Flake_Key) -> f32 {
	return arrival_puff_fraction(hash, u64(key))
}

// A candidate's birth: its slot's start plus a hashed share of the slot.
arrival_flake_birth_seconds :: proc(index: int, salt: u64) -> f32 {
	hash := arrival_flake_hash(index, salt)
	return (f32(index / ARRIVAL_FLAKE_CANDIDATES_PER_SLOT) + arrival_flake_fraction(hash, .Birth)) * ARRIVAL_FLAKE_SLOT_SECONDS
}

// A hashed value between lowest and highest.
arrival_flake_between :: proc(hash: u64, key: Arrival_Flake_Key, lowest, highest: f32) -> f32 {
	return lowest + (highest - lowest) * arrival_flake_fraction(hash, key)
}

// Candidate index at seconds (doc/presentation.md, The arrival, The
// flakes): dead outside its life, where the heat at its birth is 0, when
// its existence draw fails (the chance the rate times the heat squared)
// or without a shield. Otherwise the closed form path from its point on
// the rim and its look.
arrival_flake :: proc(index: int, seconds: f32, source: Arrival_Flake_Source) -> Arrival_Flake {
	if source.shield_radius <= 0 {
		return {}
	}
	hash := arrival_flake_hash(index, source.salt)
	birth := arrival_flake_birth_seconds(index, source.salt)
	life := arrival_flake_between(hash, .Life, ARRIVAL_FLAKE_SHORTEST_LIFE_SECONDS, ARRIVAL_FLAKE_LONGEST_LIFE_SECONDS)
	age := seconds - birth
	if age < 0 || age >= life {
		return {}
	}
	heat := arrival_heat_at_seconds(source.curve, birth, source.descent_seconds)
	if heat <= 0 {
		return {}
	}
	chance := source.flakes_per_second * heat * heat * ARRIVAL_FLAKE_SLOT_SECONDS / ARRIVAL_FLAKE_CANDIDATES_PER_SLOT
	if arrival_flake_fraction(hash, .Exists) >= chance {
		return {}
	}
	return arrival_flake_on_path(hash, age, life, heat, seconds, source)
}

// A living flake at age on its path, the model's closed form: the
// velocity against the air (n - U y) decay, relative to the pod
// U y (1 - decay) + n decay, its position integrated from the rim.
arrival_flake_on_path :: proc(hash: u64, age, life, heat, seconds: f32, source: Arrival_Flake_Source) -> Arrival_Flake {
	azimuth := arrival_flake_fraction(hash, .Azimuth) * math.TAU
	outward := [3]f32{math.cos(azimuth), 0, math.sin(azimuth)}
	sideways := [3]f32{-math.sin(azimuth), 0, math.cos(azimuth)}
	start := outward * source.shield_radius + {0, source.rim_height * arrival_flake_fraction(hash, .Height), 0}
	drag := arrival_flake_between(hash, .Drag, ARRIVAL_FLAKE_SHORTEST_DRAG_SECONDS, ARRIVAL_FLAKE_LONGEST_DRAG_SECONDS)
	nudge := outward * arrival_flake_between(hash, .Outward, ARRIVAL_FLAKE_SLOWEST_OUTWARD, ARRIVAL_FLAKE_FASTEST_OUTWARD) + sideways * ARRIVAL_FLAKE_SIDEWAYS * (2 * arrival_flake_fraction(hash, .Sideways) - 1)
	air := [3]f32{0, ARRIVAL_FLAKE_AIR_CELLS_PER_SECOND, 0}
	decay := math.exp(-age / drag)
	against_air := (nudge - air) * decay
	speed := linalg.length(against_air)
	size_share := arrival_flake_fraction(hash, .Size)
	size := ARRIVAL_FLAKE_SMALLEST_CELLS + (ARRIVAL_FLAKE_LARGEST_CELLS - ARRIVAL_FLAKE_SMALLEST_CELLS) * size_share * size_share
	fade := clamp(min(age, life - age) / ARRIVAL_FLAKE_FADE_SECONDS, 0, 1)
	return {
		position = start + air * (age - drag * (1 - decay)) + nudge * drag * (1 - decay),
		streak = -against_air / speed,
		streak_cells = ARRIVAL_FLAKE_STREAK_SECONDS * speed,
		size_cells = size,
		brightness = (0.8 + 0.4 * arrival_flake_fraction(hash, .Brightness)) * (0.35 + 0.65 * decay) * (0.5 + 0.5 * heat) * fade,
		flicker = fire_flicker(f64(seconds), hash, false),
		whiteness = 0.3 + 0.5 * decay,
		dark_core = fade,
		alive = true,
	}
}

// The living flakes of the scanned slots at the view's seconds, packed:
// the current slot and ARRIVAL_FLAKE_SLOTS_BACK before it, so at most
// MAXIMUM_ARRIVAL_FLAKES. None outside the descent, under reduced
// motion (a slowed flake never reaches a porthole), at rate 0 or
// without a shield.
arrival_flakes :: proc(view: Arrival_View, source: Arrival_Flake_Source, reduced_motion: bool) -> (flakes: [MAXIMUM_ARRIVAL_FLAKES]Arrival_Flake, count: int) {
	if view.phase != .Descent || reduced_motion || source.flakes_per_second <= 0 || source.shield_radius <= 0 {
		return
	}
	last := int(math.floor(view.seconds / ARRIVAL_FLAKE_SLOT_SECONDS))
	for slot in max(last - ARRIVAL_FLAKE_SLOTS_BACK, 0) ..= last {
		for candidate in 0 ..< ARRIVAL_FLAKE_CANDIDATES_PER_SLOT {
			flake := arrival_flake(slot * ARRIVAL_FLAKE_CANDIDATES_PER_SLOT + candidate, view.seconds, source)
			if flake.alive {
				flakes[count] = flake
				count += 1
			}
		}
	}
	return
}

// The flakes' source for the pod's machine and the view.
arrival_flake_source :: proc(curve: ^Arrival_Curve, view: Arrival_View, config: Game_Config, machine: Machine, salt: u64) -> Arrival_Flake_Source {
	return {
		curve = curve,
		descent_seconds = view.descent_seconds,
		flakes_per_second = f32(config.arrival_flakes_per_second),
		shield_radius = machine.heat_shield.radius,
		rim_height = machine.heat_shield.rim_height,
		salt = salt,
	}
}

// A flake's quad for the texture coordinates (0, 0), (1, 0), (1, 1) and
// (0, 1): x across, y from the head's front to the streak's end, turned
// about the streak's axis to face the eye.
arrival_flake_corners :: proc(head, axis, eye: [3]f32, size, length: f32) -> [4][3]f32 {
	front := head - axis * size
	back := head + axis * max(length, size)
	facing := linalg.cross(axis, eye - head)
	across := linalg.length(facing) < 1e-4 ? flame_perpendicular(axis) : linalg.normalize(facing)
	return {front - across * size, front + across * size, back + across * size, back - across * size}
}

// A share 0 to 1 as a byte.
arrival_flake_byte :: proc(share: f32) -> u8 {
	return u8(clamp(share, 0, 1) * 255 + 0.5)
}

// The flake's values as its vertex colour (arrival_flake.vs decodes
// them): the brightness times the flicker over ARRIVAL_FLAKE_BRIGHTEST
// in red, the square root of the head's share of the quad's length in
// green (a share as small as 0.02 within 2 percent, not 10, 0304),
// the whiteness in blue, the plate's opacity in alpha.
arrival_flake_vertex_color :: proc(flake: Arrival_Flake) -> [4]u8 {
	head_share := 2 * flake.size_cells / (flake.size_cells + max(flake.streak_cells, flake.size_cells))
	return {arrival_flake_byte(flake.brightness * flake.flicker / ARRIVAL_FLAKE_BRIGHTEST), arrival_flake_byte(math.sqrt(head_share)), arrival_flake_byte(flake.whiteness), arrival_flake_byte(flake.dark_core)}
}

// Inside BeginMode3D under the pod's transform, after the wake
// (draw_arrival_entry): every flake one quad of the flake shader in one
// batch, premultiplied (one, one minus source alpha), depth tested
// against the hull without writing depth, both sides drawn. The streaks'
// light adds without sorting, and the plates write alpha and hide what
// lies behind them, the wake's glow among it. The plates are not sorted
// either: they draw in slot order, so where two flakes overlap a plate
// drawn later darkens a nearer flake's light, which the flakes'
// sparseness keeps rare. Nothing without flakes or the shader.
draw_arrival_flakes :: proc(presentation: ^Arrival_Presentation, flakes: []Arrival_Flake, body: matrix[4, 4]f32, pitch_metres: f32, eye: [3]f32, haze, ablator: [3]f32) {
	if len(flakes) == 0 || !presentation.flake_ready {
		return
	}
	shader := presentation.flake_shader
	linear := cast(matrix[3, 3]f32)body
	coordinates := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	rl.BeginShaderMode(shader)
	set_shader_vector3(shader, "haze_color", haze)
	set_shader_vector3(shader, "ablator_color", ablator)
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.QUADS)
	for flake in flakes {
		color := arrival_flake_vertex_color(flake)
		head := transform_point(body, flake.position)
		corners := arrival_flake_corners(head, linalg.normalize(linear * flake.streak), eye, flake.size_cells * pitch_metres, flake.streak_cells * pitch_metres)
		rlgl.Color4ub(color.r, color.g, color.b, color.a)
		for corner, corner_index in corners {
			rlgl.TexCoord2f(coordinates[corner_index].x, coordinates[corner_index].y)
			rlgl.Vertex3f(corner.x, corner.y, corner.z)
		}
	}
	rlgl.End()
	rlgl.SetTexture(0)
	rlgl.DrawRenderBatchActive()
	rl.EndShaderMode()
	rl.EndBlendMode()
	rlgl.EnableBackfaceCulling()
	rlgl.EnableDepthMask()
}
