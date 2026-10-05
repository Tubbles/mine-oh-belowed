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
// the pod drawn base first along the curve's tangent and easing into
// the pose it rests in (arrival_pod_transform, 0270), the plasma
// streaming across the portholes' glass at the heat and lighting the
// cabin (0273), the buffeting and the roar; at the hit the pod meets the
// floor, the cabin shakes, the dust rises along the crater's rim, the
// debris flies (0272,
// render_arrival_debris.odin) and the crash and the bang play. Nothing
// here reaches the simulation, so the hash is the same with and without
// it.
// The hatch sound (play_hatch_sounds) is the general hatch cue: it plays
// for every toggle, the airlock's (0222, 0231).

ARRIVAL_VERTEX_SHADER_PATH :: "shaders/arrival.vs"
ARRIVAL_FRAGMENT_SHADER_PATH :: "shaders/arrival.fs"
// The dust curtain along the crater's rim after the hit (0272): how long
// it lasts and how many puffs it has.
ARRIVAL_DUST_SECONDS :: 4.0
ARRIVAL_DUST_PUFFS :: 64
// The hit's shake: how long it decays, its largest offset and the rate of
// its noise.
ARRIVAL_SHAKE_SECONDS :: 1.5
ARRIVAL_SHAKE_METRES :: 0.3
ARRIVAL_SHAKE_HERTZ :: 17.3
// The buffeting at the drag's peak (0269): its largest offset at heat 1
// and the rate of its noise.
ARRIVAL_BUFFET_METRES :: 0.05
ARRIVAL_BUFFET_HERTZ :: 7.3
// The portholes' flicker (0273): its mean, which reduced motion holds.
ARRIVAL_FLICKER_MEAN :: 0.85
// Each porthole's light (0273): the ablator's share of its colour, its
// brightness at heat 1 and flicker 1, its reach and how far into the
// cabin it sits from the glass, in cells.
ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE :: 0.3
ARRIVAL_WINDOW_LIGHT_GAIN :: 0.7
ARRIVAL_WINDOW_LIGHT_RADIUS_CELLS :: 5.0
ARRIVAL_WINDOW_LIGHT_INSET_CELLS :: 0.35
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
// curve's at it (arrival_curve_progress); heat 0 to 1 from the curve;
// soot 0 to 1, the soot's growth on the portholes (arrival_soot, 0273),
// set in every phase, 1 for good once the heat is out; seconds since the fall
// began (the shader's time) and since the hit; rest_share 0 to 1 over
// the descent's last arrival_real_seconds, smoothed, the drawn
// attitude's share of the resting pose (0270), 0 outside the descent.
Arrival_View :: struct {
	phase:             Arrival_Phase,
	progress:          f32,
	curve_progress:    f32,
	heat:              f32,
	soot:              f32,
	seconds:           f32,
	seconds_since_hit: f32,
	rest_share:        f32,
}

// What the sounds keep between frames: the phase of the last frame (the
// crash plays on the cut to Settled), its seconds since the hit (the
// patter plays the landings after them, 0272) and the tick up to which
// the hatches' toggles have sounded, set to the session's tick when it is
// entered, so a loaded or joined world never replays old toggles.
Arrival_Sound_Memory :: struct {
	last_phase:             Arrival_Phase,
	last_seconds_since_hit: f32,
	last_hatch_tick:        u64,
}

// The window shader, loaded with the field renderer; shader_ready false
// when it did not load, and the fall then draws without its plasma. The
// curve is built before the shader loads, so it exists without it.
Arrival_Presentation :: struct {
	curve:        Arrival_Curve,
	shader:       rl.Shader,
	shader_ready: bool,
	sound_memory: Arrival_Sound_Memory,
}

// The phase at tick plus alpha. None without a fall or after a Skip (a
// landing before the planned end); Descent until arrival_settle_ticks
// before the planned end; Settled from the hit for
// arrival_settled_seconds. The soot is set in every phase with a fall,
// from the curve's progress reached: a Skip's at its landing.
arrival_view :: proc(arrival: Field_Arrival, tick: u64, alpha: f32, config: Game_Config, curve: ^Arrival_Curve) -> Arrival_View {
	if arrival.fall_ticks == 0 {
		return {}
	}
	planned_end := arrival.start_tick + arrival.fall_ticks
	tick_rate := f32(max(config.tick_rate, 1))
	elapsed := tick < arrival.start_tick ? 0 : f32(tick - arrival.start_tick) + alpha
	descent := f32(arrival.fall_ticks) - f32(config.arrival_settle_ticks)
	if arrival.landed_tick != 0 && arrival.landed_tick < planned_end {
		reached := arrival.landed_tick < arrival.start_tick ? 0 : f32(arrival.landed_tick - arrival.start_tick)
		return {soot = arrival_reached_soot(curve, reached, descent, tick_rate)}
	}
	view := Arrival_View{seconds = elapsed / tick_rate, soot = arrival_reached_soot(curve, elapsed, descent, tick_rate)}
	switch {
	case arrival.landed_tick == 0 && elapsed < descent:
		view.phase = .Descent
		view.progress = elapsed / descent
		view.curve_progress = arrival_curve_progress(curve, view.progress, descent / tick_rate)
		view.heat = arrival_curve_at(curve, view.curve_progress).heat
		real_ticks := max(f32(config.arrival_real_seconds) * tick_rate, 1)
		view.rest_share = math.smoothstep(f32(0), 1, (elapsed - (descent - real_ticks)) / real_ticks)
	case elapsed < descent + arrival_settled_seconds(config) * tick_rate:
		view.phase = .Settled
		view.seconds_since_hit = max(elapsed - descent, 0) / tick_rate
	}
	return view
}

// The soot's growth (0273): 0 at or before the heat's peak, rising
// smoothly to 1 where the heat is out (heat_out_progress) and 1 after;
// 0 on a curve without heat.
arrival_soot :: proc(curve: ^Arrival_Curve, curve_progress: f32) -> f32 {
	if curve_progress <= curve.peak_progress || curve.heat_out_progress <= curve.peak_progress {
		return 0
	}
	return math.smoothstep(curve.peak_progress, curve.heat_out_progress, curve_progress)
}

// The soot after reached ticks of a descent of descent ticks, the
// progress clamped to 1.
arrival_reached_soot :: proc(curve: ^Arrival_Curve, reached, descent, tick_rate: f32) -> f32 {
	length := max(descent, 1)
	progress := min(reached / length, 1)
	return arrival_soot(curve, arrival_curve_progress(curve, progress, length / tick_rate))
}

// The seconds the Settled phase lasts (0272): until the dust has
// settled and the last piece of debris has flown, rested and sunk.
arrival_settled_seconds :: proc(config: Game_Config) -> f32 {
	return max(ARRIVAL_DUST_SECONDS, ARRIVAL_DEBRIS_FLIGHT_SECONDS + f32(config.arrival_debris_rest_seconds) + ARRIVAL_DEBRIS_FADE_SECONDS)
}

// The pod's and the eye's offset from their resting place during the
// descent (0223, 0269): the curve's altitude along the up and the range
// left behind the travel heading (forward: the chair's facing since
// 0270, pod_travel_heading), exactly zero at the hit, so the pod meets
// the floor there; zero outside the descent.
arrival_descent_offset :: proc(view: Arrival_View, up, forward: [3]f32, curve: ^Arrival_Curve) -> [3]f32 {
	if view.phase != .Descent {
		return {}
	}
	sample := arrival_curve_at(curve, view.curve_progress)
	return up * sample.altitude_metres - forward * (curve.range_metres - sample.along_metres)
}

// The pod's travel at a sample of the curve, unit: its tangent laid on
// the pod's up and travel heading (0269; 0270 turns the pod's base into
// it).
arrival_travel_direction :: proc(sample: Arrival_Curve_Sample, up, forward: [3]f32) -> [3]f32 {
	return linalg.normalize(forward * sample.velocity.x + up * sample.velocity.y)
}

// The rotation that takes each of the three from directions to the to
// direction of the same index (both orthonormal bases).
basis_turn :: proc(from, to: [3][3]f32) -> matrix[3, 3]f32 {
	turn: matrix[3, 3]f32
	for index in 0 ..< 3 {
		turn += linalg.outer_product(to[index], from[index])
	}
	return turn
}

// The pod base first along the travel (0270): the up turned opposite the
// travel, the travel heading onto the travel's normal in the motion's
// plane, so the chair's facing stays on the travel's side and the door's
// axis keeps its direction.
arrival_tangent_rotation :: proc(up, heading, travel: [3]f32) -> matrix[3, 3]f32 {
	normal := linalg.normalize(heading - travel * linalg.dot(heading, travel))
	return basis_turn({heading, up, linalg.cross(heading, up)}, {normal, -travel, linalg.cross(normal, -travel)})
}

// The pod's attitude, its transform about the base centre and its travel
// while it descends (0270): the tangent's rotation (arrival_tangent_rotation)
// eased by slerp into the resting pose's (pod_rest_pose) by rest_share,
// about the base centre moved by the path's offset (arrival_descent_offset
// along the travel heading). Identity and no travel outside the descent.
// The frame is the placed one, unrested until the hit.
arrival_pod_transform :: proc(view: Arrival_View, frame: Frame, pod: Entity_Common, machine: Machine, rest_tilt_degrees: int, curve: ^Arrival_Curve) -> (transform: matrix[4, 4]f32, rotation: matrix[3, 3]f32, travel: [3]f32) {
	if view.phase != .Descent {
		return 1, 1, {}
	}
	up := unit_vector_to_f32(frame.axes[FRAME_UP])
	heading := unit_vector_to_f32(pod_travel_heading(frame, pod, machine))
	travel = arrival_travel_direction(arrival_curve_at(curve, view.curve_progress), up, heading)
	_, rest_axes := pod_rest_pose(frame, pod, machine, rest_tilt_degrees)
	placed_axes, rested_axes: [3][3]f32
	for axis in 0 ..< 3 {
		placed_axes[axis], rested_axes[axis] = unit_vector_to_f32(frame.axes[axis]), unit_vector_to_f32(rest_axes[axis])
	}
	tangent := linalg.quaternion_from_matrix3_f32(arrival_tangent_rotation(up, heading, travel))
	rest := linalg.quaternion_from_matrix3_f32(basis_turn(placed_axes, rested_axes))
	rotation = linalg.matrix3_from_quaternion_f32(linalg.normalize(linalg.quaternion_slerp_f32(tangent, rest, view.rest_share)))
	base := world_position_to_metres(pod_base_centre(frame, pod))
	offset := arrival_descent_offset(view, up, heading, curve)
	transform = linalg.matrix4_translate_f32(base + offset) * linalg.matrix4_from_matrix3_f32(rotation) * linalg.matrix4_translate_f32(-base)
	return transform, rotation, travel
}

// A window's quad, its corners for the texture coordinates (0, 0), (1, 0),
// (1, 1) and (0, 1): texture y grows along the travel laid on the glass's
// plane (the fallback laid on it where the travel runs along the normal).
// draw_arrival_windows passes the fallback as the travel since 0273, so
// the quad never turns (arrival_travel_on_glass turns the flow).
arrival_window_corners :: proc(centre, normal, travel, fallback: [3]f32, radius: f32) -> [4][3]f32 {
	along := travel - normal * linalg.dot(travel, normal)
	if linalg.length(along) < 0.1 {
		along = fallback - normal * linalg.dot(fallback, normal)
	}
	along_travel := linalg.normalize(along) * radius
	across := linalg.cross(normal, linalg.normalize(along)) * radius
	return {centre - across - along_travel, centre + across - along_travel, centre + across + along_travel, centre - across + along_travel}
}

// The axis a porthole's quad and flow are laid along (0273), unit, on the
// glass's plane: the pod's up laid on it, or the pod's forward where the
// normal runs along the up.
arrival_glass_axis :: proc(normal, up, forward: [3]f32) -> [3]f32 {
	laid := up - normal * linalg.dot(up, normal)
	if linalg.length(laid) < 0.1 {
		laid = forward - normal * linalg.dot(forward, normal)
	}
	return linalg.normalize(laid)
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

// A porthole's flicker at seconds (0273): hashed value noise at two
// rates in no small ratio, so it has no period, 0.7 to 1 about
// ARRIVAL_FLICKER_MEAN; the mean under reduced motion, as the torch
// flames still. One flicker per window drives its glass and its light.
arrival_window_flicker :: proc(seconds: f32, index: int, salt: u64, reduced_motion: bool) -> f32 {
	if reduced_motion {
		return ARRIVAL_FLICKER_MEAN
	}
	window := 2 * u64(index)
	return ARRIVAL_FLICKER_MEAN + 0.1 * arrival_noise(seconds, 6.1, salt + 20 + window) + 0.05 * arrival_noise(seconds, 17.9, salt + 21 + window)
}

// The flicker of each of a pod's count windows.
arrival_window_flickers :: proc(seconds: f32, count: int, salt: u64, reduced_motion: bool) -> (flickers: [MAXIMUM_POD_WINDOWS]f32) {
	for index in 0 ..< min(count, MAXIMUM_POD_WINDOWS) {
		flickers[index] = arrival_window_flicker(seconds, index, salt, reduced_motion)
	}
	return
}

// A data colour, 0 to 255 per channel, as 0 to 1.
arrival_plasma_color :: proc(color: [3]int) -> [3]f32 {
	return {f32(color.r), f32(color.g), f32(color.b)} / 255
}

// Each porthole a point light in the plasma's colour while the pod
// descends (0273): ARRIVAL_WINDOW_LIGHT_INSET_CELLS into the cabin from
// the glass's centre, its colour the haze mixed with the ablator's share
// times the heat, the window's flicker and the gain, clipped to the pod's
// box (clip_box), so the cabin is lit and the hull's outside and the
// terrain are not. None outside the descent or at heat 0. body and
// pitch_millimetres are the pod's (entity_body_matrix); the caller moves
// the lights with the lamps (moved_point_light).
arrival_window_lights :: proc(view: Arrival_View, body: matrix[4, 4]f32, pitch_millimetres: int, machine: Machine, clip_box: matrix[4, 4]f32, plasma: Arrival_Plasma_Config, flickers: [MAXIMUM_POD_WINDOWS]f32) -> (lights: [MAXIMUM_POD_WINDOWS]Point_Light, count: int) {
	if view.phase != .Descent || view.heat <= 0 {
		return
	}
	haze, ablator := arrival_plasma_color(plasma.haze_color), arrival_plasma_color(plasma.ablator_color)
	color := haze + (ablator - haze) * ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE
	radius := ARRIVAL_WINDOW_LIGHT_RADIUS_CELLS * f32(f64(pitch_millimetres) / MILLIMETRES_PER_METRE)
	for index in 0 ..< min(machine.window_count, MAXIMUM_POD_WINDOWS) {
		window := machine.windows[index]
		lights[count] = Point_Light {
			position = transform_point(body, window.centre + window.normal * ARRIVAL_WINDOW_LIGHT_INSET_CELLS),
			color    = color * view.heat * flickers[index] * ARRIVAL_WINDOW_LIGHT_GAIN,
			radius   = radius,
			clip_box = clip_box,
		}
		count += 1
	}
	return
}

// The travel laid on a porthole's glass in the quad's basis
// (arrival_window_corners laid from the fallback alone, the glass's axis
// from arrival_glass_axis): x across, y along the fallback laid on the
// glass, unit; {0, 1} where the travel runs along the normal (or is
// zero), as the quad's fallback does.
arrival_travel_on_glass :: proc(normal, travel, fallback: [3]f32) -> [2]f32 {
	along_axis := linalg.normalize(fallback - normal * linalg.dot(fallback, normal))
	across_axis := linalg.cross(normal, along_axis)
	laid := travel - normal * linalg.dot(travel, normal)
	if linalg.length(laid) < 0.1 {
		return {0, 1}
	}
	return linalg.normalize([2]f32{linalg.dot(laid, across_axis), linalg.dot(laid, along_axis)})
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

// Puff index of the dust curtain at seconds after the hit (0272): its
// azimuth about the crater's home, its base's distance from the home
// near the rim, its drift outward, its height above the ground, its size
// and its alpha. Every value is hashed per index, so no ring or rhythm
// shows.
arrival_dust_puff :: proc(index: int, seconds_since_hit: f32, salt: u64, rim_metres: f32) -> (azimuth, base_metres, drift_metres, height_metres, size_metres, alpha: f32) {
	hash := generation_seed.hash_combine(salt, u64(index))
	seconds := max(seconds_since_hit, 0)
	azimuth = arrival_puff_fraction(hash, 0) * math.TAU
	base_metres = rim_metres * (0.9 + 0.2 * arrival_puff_fraction(hash, 1))
	speed := 2 + 3 * arrival_puff_fraction(hash, 2)
	drift_metres = speed * 0.8 * (1 - math.exp(-seconds / 0.8))
	height_metres = 0.3 + 3.5 * arrival_puff_fraction(hash, 3) * (1 - math.exp(-seconds / 1.2))
	size_metres = 1.2 + 3.5 * seconds / ARRIVAL_DUST_SECONDS
	alpha = 0.55 * math.pow(max(1 - seconds / ARRIVAL_DUST_SECONDS, 0), 1.5)
	return
}

// Inside BeginMode3D, after the scene: the dust curtain along the
// crater's rim, each puff on the ground there moved out by its drift and
// up by its height about the site's up, translucent, without writing
// depth. Nothing at or past ARRIVAL_DUST_SECONDS.
draw_arrival_dust :: proc(site: Arrival_Debris_Site, view: Arrival_View, salt: u64, color: rl.Color) {
	if view.phase != .Settled || view.seconds_since_hit >= ARRIVAL_DUST_SECONDS {
		return
	}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	for index in 0 ..< ARRIVAL_DUST_PUFFS {
		azimuth, base, drift, height, size, alpha := arrival_dust_puff(index, view.seconds_since_hit, salt, site.radius_metres)
		outward := site.east * math.cos(azimuth) + site.north * math.sin(azimuth)
		centre := arrival_debris_ground(site, azimuth, base) + outward * drift + site.up * height
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

// Inside BeginMode3D under the pod's transform (nil outside the
// descent): the plasma and the soot on each of the pod's windows (0223,
// 0273), the travel the pod's way along the path in the frame's unmoved
// space. The quad is laid from the glass's axis alone
// (arrival_glass_axis: the pod's up, its forward for a porthole facing
// along the up), so it never turns and the soot holds still; the flow
// turns inside it by travel_on_glass.
// Each window is its own batch, since its uniforms are its own; depth
// tested, without writing depth or culling. Nothing while both the heat
// and the soot are 0.
draw_arrival_windows :: proc(presentation: ^Arrival_Presentation, view: Arrival_View, entities: ^Entities, pod: Entity_Common, machine: Machine, travel: [3]f32, plasma: Arrival_Plasma_Config, flickers: [MAXIMUM_POD_WINDOWS]f32, salt: u64) {
	if (view.heat <= 0 && view.soot <= 0) || !presentation.shader_ready || machine.window_count == 0 {
		return
	}
	shader := presentation.shader
	body := entity_body_matrix(entities, pod)
	linear := cast(matrix[3, 3]f32)body
	up := linalg.normalize(linear * [3]f32{0, 1, 0})
	forward := linalg.normalize(linear * [3]f32{0, 0, 1})
	pitch_metres := f32(f64(entity_frame_pitch_millimetres(entities, pod.frame)) / MILLIMETRES_PER_METRE)
	texture := rlgl.GetTextureIdDefault()
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	rl.BeginShaderMode(shader)
	haze, ablator := arrival_plasma_color(plasma.haze_color), arrival_plasma_color(plasma.ablator_color)
	for index in 0 ..< min(machine.window_count, MAXIMUM_POD_WINDOWS) {
		window := machine.windows[index]
		centre := transform_point(body, window.centre)
		normal := linalg.normalize(linear * window.normal)
		fallback := arrival_glass_axis(normal, up, forward)
		corners := arrival_window_corners(centre, normal, fallback, fallback, window.radius * pitch_metres)
		set_shader_float(shader, "heat", view.heat)
		set_shader_float(shader, "soot", view.soot)
		set_shader_float(shader, "soot_opacity", f32(plasma.soot_percent) / 100)
		set_shader_float(shader, "seconds", view.seconds)
		set_shader_float(shader, "flame_seed", f32(salt % 1000) / 1000 + f32(index) * 0.618)
		set_shader_float(shader, "flicker", flickers[index])
		set_shader_vector2(shader, "travel_on_glass", arrival_travel_on_glass(normal, travel, fallback))
		set_shader_vector3(shader, "haze_color", haze)
		set_shader_vector3(shader, "ablator_color", ablator)
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
// the crash and the bang on the cut from the descent to the settled
// cabin, then the patter of the debris landing since the last frame
// (0272). A joiner's or a loaded world's first frame follows None and
// plays nothing, so no backlog sounds.
play_arrival_sounds :: proc(mixer: ^Audio_Mixer, memory: ^Arrival_Sound_Memory, view: Arrival_View, arrival: Field_Arrival, paused: bool, salt: u64, site: Arrival_Debris_Site, site_found: bool) {
	if view.phase == .Descent && !paused {
		set_loop_target(mixer, ARRIVAL_ROAR_SOUND, view.heat)
	}
	if memory.last_phase == .Descent && view.phase == .Settled {
		play_effect(mixer, ARRIVAL_CRASH_SOUND, 1, arrival_sound_pitch(arrival, salt, 1))
		play_effect(mixer, ARRIVAL_BANG_SOUND, 1, arrival_sound_pitch(arrival, salt, 2))
	}
	if view.phase == .Settled && site_found && (memory.last_phase == .Descent || memory.last_phase == .Settled) {
		from := memory.last_phase == .Descent ? 0 : memory.last_seconds_since_hit
		play_arrival_patter(mixer, site, from, view.seconds_since_hit, salt)
	}
	memory.last_phase = view.phase
	memory.last_seconds_since_hit = view.seconds_since_hit
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
