package game

import "core:math"
import "core:math/linalg"
import "core:slice"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "generation_seed"
import "platform"
import "render_frustum"

// Flames (work items 0061 and 0274, DESIGN.md, Fire): the flame shader
// (data/shaders/flame.vs, flame.fs) on quads, one shader for every
// burning fuel. A working furnace's flames stand where its record's
// flames say (Machine_Flame), fixed to the model; a torch's flame is one
// quad on its post, turned square to the camera about the up. The flow
// rises with the time; the flicker (the reach, the brightness, the
// firebox lamp and the embers) is hashed noise with no period. Under
// reduced motion the flicker and the embers hold at their mean and the
// flow runs at its slow layer only. Render only, nothing here reaches
// the simulation. A frame's flames are one list, nearest the camera
// first and capped (nearest_flame_draws), drawn in one batch after
// everything opaque, depth tested without depth writes, premultiplied
// (draw_flames). The shared fire flicker (fire_flicker, 0286), four
// bands of hashed noise and hashed flares and dips, drives the entry's
// portholes, and these flames keep flame_flicker until their own item.

FLAME_VERTEX_SHADER_PATH :: "shaders/flame.vs"
FLAME_FRAGMENT_SHADER_PATH :: "shaders/flame.fs"
// A block torch's flame in blocks: its width and height.
FLAME_SIZE :: 0.2
FLAME_TORCH_HEIGHT :: 0.32
// The base sits this far into the post's top, so no gap shows.
FLAME_TORCH_SINK :: 0.02
// The ramp for coal and wood: the yellow white core, the orange body and
// the dark red tips.
FLAME_CORE_COLOR :: [3]f32{1.0, 0.93, 0.72}
FLAME_BODY_COLOR :: [3]f32{1.0, 0.52, 0.12}
FLAME_TIP_COLOR :: [3]f32{0.55, 0.09, 0.02}
// The flicker's mean, held under reduced motion, and its two rates.
FLAME_FLICKER_MEAN :: 0.85
FLAME_FLICKER_SLOW_HERTZ :: 6.1
FLAME_FLICKER_FAST_HERTZ :: 17.9
// The shared fire flicker (fire_flicker, 0286): its mean, held under
// reduced motion, and its bounds.
FIRE_FLICKER_MEAN :: 0.85
FIRE_FLICKER_LOWEST :: 0.4
FIRE_FLICKER_HIGHEST :: 1.5
// One band of the fire flicker: its rate, its amplitude and whether it
// is smoothed between its steps (a linear band keeps sharp corners).
Fire_Flicker_Band :: struct {
	hertz:     f64,
	amplitude: f32,
	smooth:    bool,
}
// Four bands in no small integer ratio, the largest near the 10 to 20 Hz
// of a buoyant flame, the fastest linear for the crackle.
FIRE_FLICKER_BANDS :: [4]Fire_Flicker_Band{{2.3, 0.06, true}, {5.9, 0.09, true}, {11.3, 0.13, true}, {23.7, 0.09, false}}
// The flares and dips: one hashed event at most per slot, at a hashed
// start in it, the slots looked back over for a decaying event, the
// attack, and the shares of the slots that flare and that dip.
FIRE_FLARE_SLOT_SECONDS :: 0.2
FIRE_FLARE_SLOTS_BACK :: 3
FIRE_FLARE_ATTACK_SECONDS :: 0.025
FIRE_FLARE_SHARE :: 0.35
FIRE_DIP_SHARE :: 0.15
// The embers' slow pulse on a working furnace's emissive layer.
FLAME_EMBER_HERTZ :: 0.37
// A frame draws at most this many flames, the nearest the camera.
MAXIMUM_FLAME_DRAWS :: 256
// A field torch's flame is drawn within this distance of the camera (the
// field view's first level distance).
FLAME_DRAW_DISTANCE_METRES :: 64.0
// A quad's seed travels in a vertex colour byte: its fraction in steps
// of 1 / this, so the torches have this many flow patterns.
FLAME_SEED_STEPS :: 256

// Loaded with the model renderer (use_flame_shader); ready false when it
// did not load, and nothing burns.
// The uniform locations are looked up once, at the load.
Flame_Shader :: struct {
	shader:                rl.Shader,
	ready:                 bool,
	seconds_location:      i32,
	calm_location:         i32,
	core_color_location:   i32,
	body_color_location:   i32,
	tip_color_location:    i32,
}

// One quad of the flame shader: its corners for the texture coordinates
// (0, 0), (1, 0), (1, 1) and (0, 1), its seed shifting the noise, its
// flicker (0.7 to 1), its height over its width, and its squared
// distance to the camera (set by nearest_flame_draws).
Flame_Draw :: struct {
	corners:          [4][3]f32,
	seed:             f32,
	flicker:          f32,
	aspect:           f32,
	distance_squared: f32,
}

// The flames of the cell on the frame flicker apart from their
// neighbours'.
flame_salt :: proc(cell: World_Coordinate, frame: Frame_Id) -> u64 {
	key := u64(u32(cell.x)) ~ (u64(u32(cell.y)) << 21) ~ (u64(u32(cell.z)) << 42)
	return generation_seed.hash_combine(generation_seed.hash_u64(key), u64(frame))
}

// The salt's seed, 0 to 1 in steps of 1 / FLAME_SEED_STEPS, so salts
// one apart keep apart in the vertex colour.
flame_seed :: proc(salt: u64) -> f32 {
	return f32(salt % FLAME_SEED_STEPS) / FLAME_SEED_STEPS
}

// Value noise from -1 to 1 at hertz, smoothed between its hashed steps
// (arrival_noise_value), so it has no period; in f64, so a long session
// loses nothing.
flame_noise :: proc(seconds: f64, hertz: f64, salt: u64) -> f32 {
	at := seconds * hertz
	step := math.floor(at)
	fraction := f32(at - step)
	blend := fraction * fraction * (3 - 2 * fraction)
	first := arrival_noise_value(i64(step), salt)
	return first + (arrival_noise_value(i64(step) + 1, salt) - first) * blend
}

// 0.7 to 1: the flame's reach and brightness and its lamp's colour; the
// mean under reduced motion.
flame_flicker :: proc(seconds: f64, salt: u64, reduced_motion: bool) -> f32 {
	if reduced_motion {
		return FLAME_FLICKER_MEAN
	}
	return FLAME_FLICKER_MEAN + 0.1 * flame_noise(seconds, FLAME_FLICKER_SLOW_HERTZ, salt) + 0.05 * flame_noise(seconds, FLAME_FLICKER_FAST_HERTZ, salt + 1)
}

// One band of the fire flicker at seconds, -1 to 1: flame_noise when
// smoothed, else the same hashed steps joined by straight lines.
fire_flicker_band :: proc(seconds: f64, band: Fire_Flicker_Band, salt: u64) -> f32 {
	if band.smooth {
		return flame_noise(seconds, band.hertz, salt)
	}
	at := seconds * band.hertz
	step := math.floor(at)
	fraction := f32(at - step)
	first := arrival_noise_value(i64(step), salt)
	return first + (arrival_noise_value(i64(step) + 1, salt) - first) * fraction
}

// A fraction from 0 to 1 hashed from a flare slot's hash and a key.
fire_flare_fraction :: proc(hash: u64, key: u64) -> f32 {
	return f32(generation_seed.hash_to_unit(generation_seed.hash_combine(hash, key)))
}

// One slot's event at seconds: a flare (FIRE_FLARE_SHARE of the slots)
// or a dip (FIRE_DIP_SHARE) at a hashed start in the slot, rising over
// FIRE_FLARE_ATTACK_SECONDS and decaying after. 0 before its start and
// for a slot without one.
fire_flare_event :: proc(seconds: f64, slot: i64, salt: u64) -> f32 {
	hash := generation_seed.hash_combine(salt, u64(slot))
	start := (f64(slot) + f64(fire_flare_fraction(hash, 1))) * FIRE_FLARE_SLOT_SECONDS
	elapsed := f32(seconds - start)
	kind := fire_flare_fraction(hash, 2)
	if elapsed < 0 || kind >= FIRE_FLARE_SHARE + FIRE_DIP_SHARE {
		return 0
	}
	amplitude := 0.18 + 0.22 * fire_flare_fraction(hash, 3)
	decay := 0.06 + 0.10 * fire_flare_fraction(hash, 4)
	if kind >= FIRE_FLARE_SHARE {
		amplitude = -(0.15 + 0.15 * fire_flare_fraction(hash, 3))
		decay = 0.05 + 0.08 * fire_flare_fraction(hash, 4)
	}
	return amplitude * min(elapsed / FIRE_FLARE_ATTACK_SECONDS, 1) * math.exp(-max(elapsed - FIRE_FLARE_ATTACK_SECONDS, 0) / decay)
}

// The flares and dips at seconds: the events of this slot and the
// FIRE_FLARE_SLOTS_BACK before it, hashed per slot, so they form no
// period.
fire_flare :: proc(seconds: f64, salt: u64) -> f32 {
	slot := i64(math.floor(seconds / FIRE_FLARE_SLOT_SECONDS))
	total: f32
	for slot_index in slot - FIRE_FLARE_SLOTS_BACK ..= slot {
		total += fire_flare_event(seconds, slot_index, salt)
	}
	return total
}

// The shared fire flicker (0286), FIRE_FLICKER_LOWEST to
// FIRE_FLICKER_HIGHEST: the four bands of FIRE_FLICKER_BANDS and the
// hashed flares and dips about FIRE_FLICKER_MEAN, so it dances
// erratically with no period, and the mean under reduced motion. Pure,
// in f64, so a long session loses nothing. The portholes read it, and
// flame_flicker keeps 0274's model until the flames' own item.
fire_flicker :: proc(seconds: f64, salt: u64, reduced_motion: bool) -> f32 {
	if reduced_motion {
		return FIRE_FLICKER_MEAN
	}
	value: f32 = FIRE_FLICKER_MEAN
	for band, index in FIRE_FLICKER_BANDS {
		value += band.amplitude * fire_flicker_band(seconds, band, salt + 30 + u64(index))
	}
	value += fire_flare(seconds, salt + 40)
	return clamp(value, FIRE_FLICKER_LOWEST, FIRE_FLICKER_HIGHEST)
}

// 0.7 to 1: a working furnace's emissive layer, a slow pulse; the mean
// under reduced motion.
flame_ember_glow :: proc(seconds: f64, salt: u64, reduced_motion: bool) -> f32 {
	if reduced_motion {
		return FLAME_FLICKER_MEAN
	}
	return FLAME_FLICKER_MEAN + 0.15 * flame_noise(seconds, FLAME_EMBER_HERTZ, salt + 2)
}

// The shader's clock: the whole seconds (exact in an f32 for 194 days)
// and the fraction, so the flow's scroll keeps its precision and never
// wraps (flame.fs, scroll_at).
flame_shader_seconds :: proc(seconds: f64) -> [2]f32 {
	whole := math.floor(max(seconds, 0))
	return {f32(whole), f32(max(seconds, 0) - whole)}
}

// Bottom left, bottom right, top right, top left of a quad standing on
// its base centre.
flame_quad_corners :: proc(base, across, up: [3]f32, width, height: f32) -> [4][3]f32 {
	half := across * width / 2
	top := up * height
	return {base - half, base + half, base + half + top, base - half + top}
}

// A unit vector square to up, for a flame seen from straight above.
flame_perpendicular :: proc(up: [3]f32) -> [3]f32 {
	pick := abs(up.x) < 0.9 ? [3]f32{1, 0, 0} : [3]f32{0, 0, 1}
	return linalg.normalize(pick - up * linalg.dot(pick, up))
}

// The unit vector square to up and to the eye's offset from the base laid
// square to up, so the quad faces the eye about its up.
flame_facing_across :: proc(base, eye, up: [3]f32) -> [3]f32 {
	offset := eye - base
	level := offset - up * linalg.dot(offset, up)
	if linalg.length(level) < 0.0001 {
		return flame_perpendicular(up)
	}
	return linalg.normalize(linalg.cross(up, level))
}

// The machine's flames on its body (entity_body_matrix, or the preview's):
// the base through the body, across and up through its linear part, so
// cells become metres at the frame's pitch.
machine_flame_draws :: proc(machine: Machine, body: matrix[4, 4]f32, salt: u64, flicker: f32, draws: ^[dynamic]Flame_Draw) {
	linear := cast(matrix[3, 3]f32)body
	up := linear * [3]f32{0, 1, 0}
	for index in 0 ..< machine.flame_count {
		flame := machine.flames[index]
		corners := flame_quad_corners(transform_point(body, flame.position), linear * flame.across, up, flame.width, flame.height)
		seed := flame_seed(salt) + f32(index) * 0.618
		append(draws, Flame_Draw{corners = corners, seed = seed, flicker = flicker, aspect = flame.height / flame.width})
	}
}

// Every alive furnace whose model works and whose machine has flames,
// each flickering by its own salt; the firebox lamp reads the same
// flicker (gather_machine_lights).
gather_machine_flames :: proc(entities: ^Entities, machines: Machine_Registry, frame: Model_Frame, allocator := context.temp_allocator) -> []Flame_Draw {
	draws := make([dynamic]Flame_Draw, allocator)
	seconds := model_frame_seconds(frame)
	for furnace in entities.furnaces.entries {
		if !furnace.alive || !furnace_model_working(furnace) {
			continue
		}
		machine := machines.machines[furnace.machine]
		if machine.flame_count == 0 {
			continue
		}
		salt := flame_salt(furnace.origin, furnace.frame)
		machine_flame_draws(machine, entity_body_matrix(entities, furnace.common), salt, flame_flicker(seconds, salt, frame.reduced_motion), &draws)
	}
	return draws[:]
}

// A block torch's flame on its post, square to the eye.
torch_flame_draw :: proc(cell: World_Coordinate, eye: [3]f32, seconds: f64, reduced_motion: bool) -> Flame_Draw {
	base := [3]f32{f32(cell.x) + 0.5, f32(cell.y) + POST_HEIGHT - FLAME_TORCH_SINK, f32(cell.z) + 0.5}
	up := [3]f32{0, 1, 0}
	salt := flame_salt(cell, BLOCK_FRAME)
	corners := flame_quad_corners(base, flame_facing_across(base, eye, up), up, FLAME_SIZE, FLAME_TORCH_HEIGHT)
	return {corners = corners, seed = flame_seed(salt), flicker = flame_flicker(seconds, salt, reduced_motion), aspect = FLAME_TORCH_HEIGHT / FLAME_SIZE}
}

// The quad's values as its vertex colour (flame.vs decodes them): the
// flicker in red, the seed's fraction in green in steps of
// 1 / FLAME_SEED_STEPS (a machine flame's whole part wraps away, its
// index times 0.618 still apart), the aspect in hundredths in blue (high
// byte) and alpha (low byte).
flame_vertex_color :: proc(draw: Flame_Draw) -> [4]u8 {
	flicker := u8(clamp(draw.flicker, 0, 1) * 255 + 0.5)
	seed := u8(int(max(draw.seed, 0) * FLAME_SEED_STEPS + 0.5) % FLAME_SEED_STEPS)
	aspect := clamp(int(draw.aspect * 100 + 0.5), 0, 65535)
	return {flicker, seed, u8(aspect >> 8), u8(aspect & 255)}
}

// The draws sorted nearest the eye first (by the quad's centre), cut to
// MAXIMUM_FLAME_DRAWS.
nearest_flame_draws :: proc(draws: []Flame_Draw, eye: [3]f32) -> []Flame_Draw {
	for &draw in draws {
		centre := (draw.corners[0] + draw.corners[1] + draw.corners[2] + draw.corners[3]) / 4
		draw.distance_squared = linalg.length2(centre - eye)
	}
	slice.sort_by(draws, proc(first, second: Flame_Draw) -> bool {
		return first.distance_squared < second.distance_squared
	})
	return draws[:min(len(draws), MAXIMUM_FLAME_DRAWS)]
}

// Inside BeginMode3D, after everything opaque: every quad in one batch,
// its values in its vertex colour; premultiplied (one, one minus source
// alpha), so the quads need no sorting by depth; depth tested without
// depth writes or culling. Nothing when the shader did not load.
draw_flames :: proc(flame: Flame_Shader, draws: []Flame_Draw, seconds: f64, reduced_motion: bool) {
	if !flame.ready || len(draws) == 0 {
		return
	}
	seconds_value := flame_shader_seconds(seconds)
	calm: f32 = reduced_motion ? 1 : 0
	core, body, tip := FLAME_CORE_COLOR, FLAME_BODY_COLOR, FLAME_TIP_COLOR
	coordinates := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	rl.BeginShaderMode(flame.shader)
	rl.SetShaderValue(flame.shader, flame.seconds_location, &seconds_value, .VEC2)
	rl.SetShaderValue(flame.shader, flame.calm_location, &calm, .FLOAT)
	rl.SetShaderValue(flame.shader, flame.core_color_location, &core, .VEC3)
	rl.SetShaderValue(flame.shader, flame.body_color_location, &body, .VEC3)
	rl.SetShaderValue(flame.shader, flame.tip_color_location, &tip, .VEC3)
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.QUADS)
	for draw in draws {
		color := flame_vertex_color(draw)
		rlgl.Color4ub(color.r, color.g, color.b, color.a)
		for corner, index in draw.corners {
			rlgl.TexCoord2f(coordinates[index].x, coordinates[index].y)
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

// The torches of the chunk meshes in the camera's frustum (as draw_chunks
// culls them), appended.
append_torch_flames :: proc(draws: ^[dynamic]Flame_Draw, renderer: ^Chunk_Renderer, camera: rl.Camera3D, seconds: f64, reduced_motion: bool) {
	view_projection := rlgl.GetMatrixProjection() * rl.GetCameraMatrix(camera)
	frustum := render_frustum.frustum_from_matrix(cast(matrix[4, 4]f32)view_projection)
	for coordinate, chunk_render in renderer.chunk_meshes {
		if len(chunk_render.flames) == 0 || !chunk_in_frustum(frustum, coordinate) {
			continue
		}
		for cell in chunk_render.flames {
			append(draws, torch_flame_draw(cell, camera.position, seconds, reduced_motion))
		}
	}
}

// The block world's flames: the working furnaces' and the torches', one
// list on the tick clock, so a paused game stills them.
draw_session_flames :: proc(renderer: ^Chunk_Renderer, models: Model_Renderer, entities: ^Entities, machines: Machine_Registry, camera: rl.Camera3D, frame: Model_Frame) {
	seconds := model_frame_seconds(frame)
	draws := make([dynamic]Flame_Draw, context.temp_allocator)
	append(&draws, ..gather_machine_flames(entities, machines, frame))
	append_torch_flames(&draws, renderer, camera, seconds, frame.reduced_motion)
	draw_flames(models.flame, nearest_flame_draws(draws[:], camera.position), seconds, frame.reduced_motion)
}

// The lit layer's companion: the flame shader; when it does not load, a
// log line, and nothing burns.
use_flame_shader :: proc(renderer: ^Model_Renderer, data_directory: string) {
	shader, ok := load_shader_pair(data_directory, FLAME_VERTEX_SHADER_PATH, FLAME_FRAGMENT_SHADER_PATH, "flame")
	if !ok {
		platform.log_printf("models: the flame shader did not load; machines and torches draw without flames")
		return
	}
	renderer.flame = Flame_Shader {
		shader              = shader,
		ready               = true,
		seconds_location    = rl.GetShaderLocation(shader, "seconds"),
		calm_location       = rl.GetShaderLocation(shader, "calm"),
		core_color_location = rl.GetShaderLocation(shader, "core_color"),
		body_color_location = rl.GetShaderLocation(shader, "body_color"),
		tip_color_location  = rl.GetShaderLocation(shader, "tip_color"),
	}
}
