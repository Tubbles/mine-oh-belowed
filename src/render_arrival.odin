package game

import "core:math"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "generation_seed"
import "platform"

// The arrival's presentation (work item 0200, doc/presentation.md, The
// field session, The arrival): render only, read from Field_Arrival
// (simulation_arrival.odin), the tick and the interpolation alpha. The
// descent moves the seated eye and the pod round it along the entry's
// curve down to the resting place (arrival_descent_offset, 0223, 0269),
// the flames burning on the portholes' glass at the heat, the buffeting
// and the roar; at the hit the pod meets
// the floor, the cabin shakes, the dust rises outside and the crash
// plays. Nothing here
// reaches the simulation, so the hash is the same with and without it.
// The hatch sound (play_hatch_sounds) is the general hatch cue: it plays
// for every toggle, the airlock's (0222, 0231).

ARRIVAL_VERTEX_SHADER_PATH :: "shaders/arrival.vs"
ARRIVAL_FRAGMENT_SHADER_PATH :: "shaders/arrival.fs"
// The dust outside the pod after the hit: how long it lasts and how many
// puffs it has.
ARRIVAL_DUST_SECONDS :: 4.0
ARRIVAL_DUST_PUFFS :: 36
// The hit's shake: how long it decays, its largest offset and the rate of
// its noise.
ARRIVAL_SHAKE_SECONDS :: 1.0
ARRIVAL_SHAKE_METRES :: 0.15
ARRIVAL_SHAKE_HERTZ :: 17.3
// The buffeting at the drag's peak (0269): its largest offset at heat 1
// and the rate of its noise.
ARRIVAL_BUFFET_METRES :: 0.05
ARRIVAL_BUFFET_HERTZ :: 7.3
ARRIVAL_ROAR_SOUND :: "arrival_roar"
ARRIVAL_CRASH_SOUND :: "arrival_crash"
HATCH_SLIDE_SOUND :: "hatch_slide"
// Each sound's pitch varies by up to this share either way.
ARRIVAL_PITCH_SHARE :: 0.06

Arrival_Phase :: enum u8 {
	None,
	Descent,
	Settled,
}

// progress runs 0 to 1 over the descent (not eased), curve_progress the
// curve's at it (arrival_curve_progress); heat 0 to 1 from the curve,
// cooling 0 up to the heat's peak and 1 after it; seconds since the fall
// began (the shader's time) and since the hit.
Arrival_View :: struct {
	phase:             Arrival_Phase,
	progress:          f32,
	curve_progress:    f32,
	heat:              f32,
	cooling:           f32,
	seconds:           f32,
	seconds_since_hit: f32,
}

// What the sounds keep between frames: the phase of the last frame (the
// crash plays on the cut to Settled) and the tick up to which the
// hatches' toggles have sounded, set to the session's tick when it is
// entered, so a loaded or joined world never replays old toggles.
Arrival_Sound_Memory :: struct {
	last_phase:      Arrival_Phase,
	last_hatch_tick: u64,
}

// The window shader, loaded with the field renderer; shader_ready false
// when it did not load, and the fall then draws without its flames. The
// curve is built before the shader loads, so it exists without it.
Arrival_Presentation :: struct {
	curve:        Arrival_Curve,
	shader:       rl.Shader,
	shader_ready: bool,
	sound_memory: Arrival_Sound_Memory,
}

// The phase at tick plus alpha. None without a fall or after a Skip (a
// landing before the planned end); Descent until arrival_settle_ticks
// before the planned end; Settled from the hit for ARRIVAL_DUST_SECONDS.
arrival_view :: proc(arrival: Field_Arrival, tick: u64, alpha: f32, config: Game_Config, curve: ^Arrival_Curve) -> Arrival_View {
	planned_end := arrival.start_tick + arrival.fall_ticks
	if arrival.fall_ticks == 0 || (arrival.landed_tick != 0 && arrival.landed_tick < planned_end) {
		return {}
	}
	tick_rate := f32(max(config.tick_rate, 1))
	elapsed := tick < arrival.start_tick ? 0 : f32(tick - arrival.start_tick) + alpha
	descent := f32(arrival.fall_ticks) - f32(config.arrival_settle_ticks)
	view := Arrival_View{seconds = elapsed / tick_rate}
	switch {
	case arrival.landed_tick == 0 && elapsed < descent:
		view.phase = .Descent
		view.progress = elapsed / descent
		view.curve_progress = arrival_curve_progress(curve, view.progress, descent / tick_rate)
		view.heat = arrival_curve_at(curve, view.curve_progress).heat
		view.cooling = view.curve_progress > curve.peak_progress ? 1 : 0
	case elapsed < descent + ARRIVAL_DUST_SECONDS * tick_rate:
		view.phase = .Settled
		view.seconds_since_hit = max(elapsed - descent, 0) / tick_rate
	}
	return view
}

// The pod's and the eye's offset from their resting place during the
// descent (0223, 0269): the curve's altitude along the up and the range
// left along the back, exactly zero at the hit, so the pod meets the
// floor there; zero outside the descent.
arrival_descent_offset :: proc(view: Arrival_View, up, forward: [3]f32, curve: ^Arrival_Curve) -> [3]f32 {
	if view.phase != .Descent {
		return {}
	}
	sample := arrival_curve_at(curve, view.curve_progress)
	return up * sample.altitude_metres - forward * (curve.range_metres - sample.along_metres)
}

// The pod's travel at a sample of the curve, unit: its tangent laid on
// the pod's up and forward (0269; 0270 turns the pod's base into it).
arrival_travel_direction :: proc(sample: Arrival_Curve_Sample, up, forward: [3]f32) -> [3]f32 {
	return linalg.normalize(forward * sample.velocity.x + up * sample.velocity.y)
}

// A window's quad, its corners for the texture coordinates (0, 0), (1, 0),
// (1, 1) and (0, 1): texture y grows along the travel laid on the glass's
// plane (the fallback laid on it where the travel runs along the normal),
// so the shader's flames lead on that edge.
arrival_window_corners :: proc(centre, normal, travel, fallback: [3]f32, radius: f32) -> [4][3]f32 {
	along := travel - normal * linalg.dot(travel, normal)
	if linalg.length(along) < 0.1 {
		along = fallback - normal * linalg.dot(fallback, normal)
	}
	along_travel := linalg.normalize(along) * radius
	across := linalg.cross(normal, linalg.normalize(along)) * radius
	return {centre - across - along_travel, centre + across - along_travel, centre + across + along_travel, centre - across + along_travel}
}

// A hashed value from -1 to 1 for each whole step of the noise.
arrival_noise_value :: proc(step: i64, salt: u64) -> f32 {
	return f32(generation_seed.hash_to_unit(generation_seed.hash_combine(salt, u64(step)))) * 2 - 1
}

// Value noise from -1 to 1 at hertz, smoothed between its hashed steps,
// so it has no period.
arrival_noise :: proc(seconds: f32, hertz: f64, salt: u64) -> f32 {
	at := f64(seconds) * hertz
	step := math.floor(at)
	fraction := f32(at - step)
	blend := fraction * fraction * (3 - 2 * fraction)
	first := arrival_noise_value(i64(step), salt)
	return first + (arrival_noise_value(i64(step) + 1, salt) - first) * blend
}

// The hit's shake at seconds after it: the eye's offset and the look's,
// half as large; both fade out over ARRIVAL_SHAKE_SECONDS.
arrival_shake_offset :: proc(seconds_since_hit: f32, salt: u64) -> (position, look: [3]f32) {
	if seconds_since_hit < 0 || seconds_since_hit >= ARRIVAL_SHAKE_SECONDS {
		return
	}
	fade := 1 - seconds_since_hit / ARRIVAL_SHAKE_SECONDS
	amplitude := ARRIVAL_SHAKE_METRES * fade * fade
	position = [3]f32{arrival_noise(seconds_since_hit, ARRIVAL_SHAKE_HERTZ, salt), arrival_noise(seconds_since_hit, ARRIVAL_SHAKE_HERTZ, salt + 1), arrival_noise(seconds_since_hit, ARRIVAL_SHAKE_HERTZ, salt + 2)} * amplitude
	look = [3]f32{arrival_noise(seconds_since_hit, ARRIVAL_SHAKE_HERTZ, salt + 3), arrival_noise(seconds_since_hit, ARRIVAL_SHAKE_HERTZ, salt + 4), arrival_noise(seconds_since_hit, ARRIVAL_SHAKE_HERTZ, salt + 5)} * amplitude * 0.5
	return
}

// The buffeting at seconds into the fall (0269): the eye's offset and the
// look's, half as large, ARRIVAL_BUFFET_METRES times the heat cubed, so
// it shakes only round the drag's peak.
arrival_buffet_offset :: proc(seconds, heat: f32, salt: u64) -> (position, look: [3]f32) {
	amplitude := ARRIVAL_BUFFET_METRES * heat * heat * heat
	if amplitude <= 0 {
		return
	}
	position = [3]f32{arrival_noise(seconds, ARRIVAL_BUFFET_HERTZ, salt + 8), arrival_noise(seconds, ARRIVAL_BUFFET_HERTZ, salt + 9), arrival_noise(seconds, ARRIVAL_BUFFET_HERTZ, salt + 10)} * amplitude
	look = [3]f32{arrival_noise(seconds, ARRIVAL_BUFFET_HERTZ, salt + 11), arrival_noise(seconds, ARRIVAL_BUFFET_HERTZ, salt + 12), arrival_noise(seconds, ARRIVAL_BUFFET_HERTZ, salt + 13)} * amplitude * 0.5
	return
}

// A fraction from 0 to 1 hashed from a puff's hash and a key.
arrival_puff_fraction :: proc(hash: u64, key: u64) -> f32 {
	return f32(generation_seed.hash_to_unit(generation_seed.hash_combine(hash, key)))
}

// Puff index of the dust at seconds after the hit: its distance from the
// pod's centre, its height, its size, its alpha and its angle about the
// up. Every value is hashed per index, so no ring or rhythm shows.
arrival_dust_puff :: proc(index: int, seconds_since_hit: f32, salt: u64) -> (radius_metres, height_metres, size_metres, alpha: f32, angle: f32) {
	hash := generation_seed.hash_combine(salt, u64(index))
	seconds := max(seconds_since_hit, 0)
	angle = arrival_puff_fraction(hash, 0) * math.TAU
	speed := 2 + 3 * arrival_puff_fraction(hash, 2)
	radius_metres = 3.5 + 1.5 * arrival_puff_fraction(hash, 1) + speed * 0.8 * (1 - math.exp(-seconds / 0.8))
	height_metres = 0.3 + 1.8 * arrival_puff_fraction(hash, 3) * (1 - math.exp(-seconds / 1.2))
	size_metres = 0.8 + 2.5 * seconds / ARRIVAL_DUST_SECONDS
	alpha = 0.55 * math.pow(max(1 - seconds / ARRIVAL_DUST_SECONDS, 0), 1.5)
	return
}

// Inside BeginMode3D, after the scene: the dust round the pod's frame,
// translucent, without writing depth.
draw_arrival_dust :: proc(frame: Frame, view: Arrival_View, salt: u64, color: rl.Color) {
	origin := world_position_to_metres(frame.origin)
	right := unit_vector_to_f32(frame.axes[FRAME_RIGHT])
	up := unit_vector_to_f32(frame.axes[FRAME_UP])
	forward := unit_vector_to_f32(frame.axes[FRAME_FORWARD])
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	for index in 0 ..< ARRIVAL_DUST_PUFFS {
		radius, height, size, alpha, angle := arrival_dust_puff(index, view.seconds_since_hit, salt)
		centre := origin + (right * math.cos(angle) + forward * math.sin(angle)) * radius + up * height
		rl.DrawSphereEx(centre, size * 0.5, 6, 8, rl.Fade(color, alpha))
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

// The entry's curve, then the window shader; on its failure a log line,
// and the fall still plays.
init_arrival_presentation :: proc(data_directory: string, config: Game_Config) -> Arrival_Presentation {
	presentation := Arrival_Presentation{curve = build_arrival_curve(config)}
	shader, ok := load_shader_pair(data_directory, ARRIVAL_VERTEX_SHADER_PATH, ARRIVAL_FRAGMENT_SHADER_PATH, "arrival")
	if !ok {
		platform.log_printf("arrival: the window shader did not load; the fall draws without its window")
		return presentation
	}
	presentation.shader = shader
	presentation.shader_ready = true
	return presentation
}

destroy_arrival_presentation :: proc(presentation: ^Arrival_Presentation) {
	if presentation.shader_ready {
		rl.UnloadShader(presentation.shader)
	}
	presentation.shader = {}
	presentation.shader_ready = false
}

// Inside BeginMode3D during the descent, moved with the pod: the
// flames on each of the pod's windows (0223), the travel the pod's way
// along the path. Each window is its own batch, since its seed is its
// own; depth tested, without writing depth or culling. Nothing at heat 0.
draw_arrival_windows :: proc(presentation: ^Arrival_Presentation, view: Arrival_View, entities: ^Entities, pod: Entity_Common, machine: Machine, travel: [3]f32, salt: u64) {
	if view.phase != .Descent || view.heat <= 0 || !presentation.shader_ready || machine.window_count == 0 {
		return
	}
	shader := presentation.shader
	body := entity_body_matrix(entities, pod)
	linear := cast(matrix[3, 3]f32)body
	fallback := linalg.normalize(linear * [3]f32{0, 1, 0})
	pitch_metres := f32(f64(entity_frame_pitch_millimetres(entities, pod.frame)) / MILLIMETRES_PER_METRE)
	texture := rlgl.GetTextureIdDefault()
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	rl.BeginShaderMode(shader)
	for index in 0 ..< machine.window_count {
		window := machine.windows[index]
		centre := transform_point(body, window.centre)
		normal := linalg.normalize(linear * window.normal)
		corners := arrival_window_corners(centre, normal, travel, fallback, window.radius * pitch_metres)
		set_shader_float(shader, "heat", view.heat)
		set_shader_float(shader, "cooling", view.cooling)
		set_shader_float(shader, "seconds", view.seconds)
		set_shader_float(shader, "flame_seed", f32(salt % 1000) / 1000 + f32(index) * 0.618)
		coordinates := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
		rlgl.SetTexture(texture)
		rlgl.Begin(rlgl.QUADS)
		rlgl.Color4ub(255, 255, 255, 255)
		for corner, corner_index in corners {
			rlgl.TexCoord2f(coordinates[corner_index].x, coordinates[corner_index].y)
			rlgl.Vertex3f(corner.x, corner.y, corner.z)
		}
		rlgl.End()
		rlgl.SetTexture(0)
		rlgl.DrawRenderBatchActive()
	}
	rl.EndShaderMode()
	rlgl.EnableBackfaceCulling()
	rlgl.EnableDepthMask()
}

// The pitch of one of the arrival's sounds, varied per world.
arrival_sound_pitch :: proc(arrival: Field_Arrival, salt: u64, sound: u64) -> f32 {
	return 1 + ARRIVAL_PITCH_SHARE * (2 * hash_fraction(sound_hash(arrival.start_tick, sound, salt)) - 1)
}

// Once a frame: the roar at the heat while the pod descends
// (fading out under the pause menu, which stops an offline world's tick),
// the crash on the cut from the descent to the settled cabin.
play_arrival_sounds :: proc(mixer: ^Audio_Mixer, memory: ^Arrival_Sound_Memory, view: Arrival_View, arrival: Field_Arrival, paused: bool, salt: u64) {
	if view.phase == .Descent && !paused {
		set_loop_target(mixer, ARRIVAL_ROAR_SOUND, view.heat)
	}
	if memory.last_phase == .Descent && view.phase == .Settled {
		play_effect(mixer, ARRIVAL_CRASH_SOUND, 1, arrival_sound_pitch(arrival, salt, 1))
	}
	memory.last_phase = view.phase
}

// Once a frame, the general hatch cue: hatch_slide once for every alive
// hatch whose toggle tick lies after the last frame's tick and at or
// before this one, opening and closing alike, its pitch varied by its
// handle, its toggle tick and the salt.
play_hatch_sounds :: proc(mixer: ^Audio_Mixer, memory: ^Arrival_Sound_Memory, entities: ^Entities, tick: u64, salt: u64) {
	for entry in entities.foundations.entries {
		if entry.alive && entry.hatch_toggle_tick > memory.last_hatch_tick && entry.hatch_toggle_tick <= tick {
			hash := sound_hash(entry.hatch_toggle_tick, u64(entry.handle.index) << 32 | u64(entry.handle.generation), salt)
			play_effect(mixer, HATCH_SLIDE_SOUND, 1, 1 + ARRIVAL_PITCH_SHARE * (2 * hash_fraction(hash) - 1))
		}
	}
	memory.last_hatch_tick = tick
}
