package game

import "core:fmt"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"

// The planet preview (--planet-preview, work item 0169): a window with the
// fly camera over the terrain field of the home planet, streamed and
// meshed with the level of detail and drawn with the field shader. No
// simulation, no UI but a line of counts. A viewing tool until the slice
// switches the session to the field world (0179); the field items 0170 to
// 0173 extend it. Escape closes it.
//
// The walk key (PLANET_PREVIEW_WALK_KEY, 0170) switches between the free
// camera and the field player standing on the surface under it: the
// player's controller ticks at the game's tick rate on the raylib input,
// the field streams round the player, and the camera follows its eye with
// its up. The walk key again returns the free camera to the eye.
//
// Walking, the hand tool digs and places (0171, field_mining.odin) through
// the tick's edit queue: Mine digs and Place places with the brush
// (mouse buttons, the triggers), Rotate_Building (R, North) cycles the
// brushes of data/game.sjson and Hotbar_Next (the wheel, ], the right
// shoulder) the held material. The player carries PLANET_PREVIEW_TOOL_ITEM
// in a small inventory, so the real yield runs; a second line names the
// brush, the held material, the material and tint under the reticle, the
// volume held per material and why the latest edit was refused.
//
// Past the last material the held material cycle holds a foundation
// (0174, entity_frames.odin): Place puts one against the face of the
// targeted frame's cell, which joins that frame, or free on the targeted
// ground, which starts a new frame. The player carries
// PLANET_PREVIEW_FOUNDATION_COUNT of them. The frames are drawn as boxes
// per cell (render_frames.odin) with a see-through ghost where Place
// would put the next one.
//
// With a screenshot path (--planet-preview-screenshot) it takes no input:
// the camera stays above the pole's ground just inside the finest level's
// distance, so the finest nodes lie under it and the horizon as far out as
// it can be, tilted by PLANET_PREVIEW_SCREENSHOT_PITCH,
// the frames run until PLANET_PREVIEW_SCREENSHOT_FRAMES have passed and the
// streaming has settled (at most PLANET_PREVIEW_SCREENSHOT_FRAME_LIMIT),
// and the last frame is saved to the path. With --planet-preview-walk the
// frame is the field player's instead, standing on the pole's ground, one
// tick a frame: once it stands and the field has streamed, a pit is dug
// ahead of it with a torch at its bottom (0173, dig_planet_preview_pit)
// and the camera tilts down into it, and the frame is taken once the
// light has spread.
//
// The field light (0173): the torch key (PLANET_PREVIEW_TORCH_KEY, L)
// places a torch of data/lighting.sjson at the air sample in front of the
// targeted ground, or takes away the torch there; the session connects the
// torch entity to the light in the slice (0179). --planet-preview-daylight
// sets the sky light's share in percent (the field shader's daylight), so
// a torch's room shows at night (0).
//
// Once the player stands, a pad of foundations is laid 9 m ahead as well
// (0174, lay_planet_preview_foundations), past the pit, so a shot tilted
// less shows a frame.

PLANET_PREVIEW_PLANET :: "home"
PLANET_PREVIEW_START_HEIGHT_METRES :: 40
PLANET_PREVIEW_START_PITCH :: -25
// The cameras look towards longitude -105 (a yaw of 255 degrees looks
// along longitude 255), where the default seed's hollows below the sea
// level (data/planets.sjson) lie 70 to 500 m from the pole, so the start
// shows the sea (0172).
PLANET_PREVIEW_START_YAW :: 255
// Above this height the fly speed grows in proportion, so the globe is a
// short flight away.
PLANET_PREVIEW_SPEED_HEIGHT_METRES :: 32
PLANET_PREVIEW_NEAR_METRES :: 0.5
// The far plane in planet radii, so the whole globe fits.
PLANET_PREVIEW_FAR_RADII :: 4
PLANET_PREVIEW_WINDOW_WIDTH :: 1280
PLANET_PREVIEW_WINDOW_HEIGHT :: 720
PLANET_PREVIEW_FIELD_OF_VIEW :: 70
PLANET_PREVIEW_TEXT_SIZE :: 20
// The screenshot camera's height below the finest level's distance, and
// its tilt below the horizon, so the level seams lie ahead.
PLANET_PREVIEW_SCREENSHOT_CLEARANCE_METRES :: 2
PLANET_PREVIEW_SCREENSHOT_PITCH :: -8
PLANET_PREVIEW_SCREENSHOT_FRAMES :: 120
PLANET_PREVIEW_SCREENSHOT_FRAME_LIMIT :: 1200
PLANET_PREVIEW_WALK_KEY :: rl.KeyboardKey.G
// The field player starts this far above the generated surface and drops.
PLANET_PREVIEW_WALK_CLEARANCE_MILLIMETRES :: 250
// A slow frame runs at most this many ticks; the rest of the time is
// dropped.
PLANET_PREVIEW_MAXIMUM_TICKS_PER_FRAME :: 5
// The preview's player carries this pickaxe, so every material with an
// item digs (0171).
PLANET_PREVIEW_TOOL_ITEM :: "iron_pickaxe"
PLANET_PREVIEW_TORCH_KEY :: rl.KeyboardKey.L
// The emitter of data/lighting.sjson the torch key places.
PLANET_PREVIEW_TORCH_EMITTER :: "torch"
// The screenshot's pit: a sphere dug this far ahead of the feet and this
// deep below them, open at the top, and the camera's tilt down into it.
PLANET_PREVIEW_PIT_RADIUS_MILLIMETRES :: 2500
PLANET_PREVIEW_PIT_AHEAD_MILLIMETRES :: 3300
PLANET_PREVIEW_PIT_DEPTH_MILLIMETRES :: 1500
PLANET_PREVIEW_PIT_PITCH_DEGREES :: -50
PLANET_PREVIEW_FOUNDATION_COUNT :: 100
// The walk screenshot's pad: this far ahead of the feet (past the pit), this many cells
// either side of the first foundation, and a column this high on it.
PLANET_PREVIEW_PAD_DISTANCE_MILLIMETRES :: 9000
PLANET_PREVIEW_PAD_HALF_WIDTH :: 2
PLANET_PREVIEW_PAD_COLUMN_HEIGHT :: 3

Planet_Preview :: struct {
	planet:          Planet,
	level_distances: [FIELD_LEVEL_COUNT]int,
	camera:          Fly_Camera,
	// The field world and its one player with a small inventory, so the
	// real yield code runs (0171).
	field:           Field_Simulation,
	field_content:   Field_Simulation_Content,
	streaming:       Field_Streaming,
	renderer:        Field_Renderer,
	input_bindings:  Input_Bindings,
	pressed:         Action_Set,
	// Empty for the interactive preview.
	screenshot_path: string,
	seed:            u64,
	tick_rate:       int,
	// The walk mode (0170): the field player instead of the free camera.
	walking:         bool,
	// Frame time not yet run as ticks, the input gathered for the next
	// tick, the buttons held on the latest frame (the held buttons of a
	// tick after the first of a frame) and the turn short of a whole angle
	// unit.
	tick_seconds:    f32,
	pending:         Field_Player_Input,
	held_now:        Field_Player_Buttons,
	turn_remainder:  [2]f32,
	tick:            u64,
	// The torch's level (data/lighting.sjson) and whether the screenshot's
	// pit is dug (0173).
	torch_level:     u8,
	pit_dug:         bool,
	// The walk screenshot's foundations are laid (once).
	pad_laid:        bool,
	// The arms on the pad (0175, loop_planet_preview_arms.odin): their
	// models, the items they could hold, and the one posed at full reach.
	models:          Model_Renderer,
	items:           Item_Registry,
	reaching_arm:    Entity_Handle,
}

planet_preview_speed_scale :: proc(height_metres: f32) -> f32 {
	return max(1, height_metres / PLANET_PREVIEW_SPEED_HEIGHT_METRES)
}

// Metres from the planet's centre into fixed point, inside the generation's
// far limit.
metres_to_world_position :: proc(position: [3]f32) -> World_Position {
	limit := f32(FAR_LIMIT_METRES)
	world: World_Position
	for axis in 0 ..< 3 {
		world[axis] = i64(clamp(position[axis], -limit, limit) * POSITION_UNITS_PER_METRE)
	}
	return world
}

// Above the planet's pole on +y, where the fly camera's up is the planet's.
planet_preview_start_camera :: proc(planet: Planet) -> Fly_Camera {
	return Fly_Camera{position = {0, f32(planet.radius_metres + PLANET_PREVIEW_START_HEIGHT_METRES), 0}, yaw = PLANET_PREVIEW_START_YAW, pitch = PLANET_PREVIEW_START_PITCH}
}

// Above the pole's local ground (the generation's surface there) by the
// finest distance less the clearance: the node holding that ground is then
// nearer than the finest distance.
planet_preview_screenshot_camera :: proc(planet: Planet, seed: u64, finest_distance_metres: int) -> Fly_Camera {
	generation := make_planet_generation(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	pole := [3]i64{0, generation.radius, 0}
	ground := f32(generation.radius + surface_relief(generation.surface_seed, pole)) / POSITION_UNITS_PER_METRE
	return Fly_Camera{position = {0, ground + f32(finest_distance_metres - PLANET_PREVIEW_SCREENSHOT_CLEARANCE_METRES), 0}, yaw = PLANET_PREVIEW_START_YAW, pitch = PLANET_PREVIEW_SCREENSHOT_PITCH}
}

// Every selected node has been meshed and nothing is pending.
field_streaming_settled :: proc(streaming: ^Field_Streaming, selection: []Field_Node) -> bool {
	if streaming.pending_jobs > 0 {
		return false
	}
	for node in selection {
		if node not_in streaming.mesh_revisions {
			return false
		}
	}
	return true
}

planet_preview_screenshot_due :: proc(frame: int, settled: bool) -> bool {
	return frame >= PLANET_PREVIEW_SCREENSHOT_FRAME_LIMIT || (frame >= PLANET_PREVIEW_SCREENSHOT_FRAMES && settled)
}

// Read from the back buffer before the swap; raylib's TakeScreenshot would
// drop the path's directories and report no failure.
save_planet_preview_screenshot :: proc(path: string) -> bool {
	image := rl.LoadImageFromScreen()
	defer rl.UnloadImage(image)
	return rl.ExportImage(image, fmt.ctprintf("%s", path))
}

fly_planet_preview :: proc(preview: ^Planet_Preview, frame_seconds: f32) {
	input := read_raylib_input_frame(preview.pressed, preview.input_bindings, {})
	preview.pressed = input.pressed
	preview.camera = turn_fly_camera(preview.camera, input, frame_seconds)
	height := linalg.length(preview.camera.position) - f32(preview.planet.radius_metres)
	velocity := fly_camera_velocity(preview.camera, input, .Sprint in input.pressed)
	preview.camera.position += velocity * planet_preview_speed_scale(height) * frame_seconds
}

// One frame's turn in angle units at the fly camera's rates: x right, y
// up.
frame_turn_angle_units :: proc(frame: Input_Frame, frame_seconds: f32) -> [2]f32 {
	stick_degrees := frame.look * FLY_CAMERA_STICK_DEGREES_PER_SECOND * frame_seconds
	pointer_degrees := frame.look_delta * FLY_CAMERA_DEGREES_PER_LOOK_PIXEL
	return [2]f32{stick_degrees.x + pointer_degrees.x, stick_degrees.y - pointer_degrees.y} * ANGLE_UNITS_PER_TURN / 360
}

// The whole angle units of the turn and the remainder carried to the next
// frame, so a slow stick turn is not lost to truncation.
carry_turn :: proc(remainder, turn: [2]f32) -> (whole: [2]i32, rest: [2]f32) {
	total := remainder + turn
	whole = {i32(total.x), i32(total.y)}
	return whole, total - {f32(whole.x), f32(whole.y)}
}

// One frame's raylib input as the field player's integers, the stick in
// thousandths. Sprint sprints while held (the toggle setting is the
// session's, 0179); the preview is a developer tool, so the Jump double
// tap flies.
field_player_input_from_frame :: proc(frame: Input_Frame, turn: [2]i32) -> Field_Player_Input {
	input := Field_Player_Input {
		move      = {i32(clamp(frame.move.x, -1, 1) * FIELD_MOVE_ONE), i32(clamp(frame.move.y, -1, 1) * FIELD_MOVE_ONE)},
		turn      = turn,
		developer = true,
	}
	buttons := [?]struct {
		action: Action,
		button: Field_Player_Button,
	}{{.Jump, .Jump}, {.Sneak, .Sneak}, {.Sprint, .Sprint}, {.Sprint_Hold, .Sprint}, {.Toggle_Fly_Mode, .Toggle_Fly_Mode}, {.Toggle_No_Clip, .Toggle_No_Clip}, {.Toggle_Camera_Mode, .Toggle_Camera_Mode}, {.Mine, .Dig}, {.Place, .Place}, {.Rotate_Building, .Next_Brush}, {.Hotbar_Next, .Next_Material}}
	for entry in buttons {
		if entry.action in frame.pressed {
			input.held += {entry.button}
		}
		if entry.action in frame.just_pressed {
			input.just_pressed += {entry.button}
		}
	}
	return input
}

// Frames between ticks add their turns and their presses, and a button
// held on any of them is held for the tick, so a Jump pressed and released
// between two ticks still jumps; the latest move stands.
merge_field_player_input :: proc(pending, next: Field_Player_Input) -> Field_Player_Input {
	merged := next
	merged.turn += pending.turn
	merged.held += pending.held
	merged.just_pressed += pending.just_pressed
	return merged
}

// The field player standing on the generated surface under the free
// camera, heading where the camera looks.
start_planet_preview_walk :: proc(preview: ^Planet_Preview) {
	generation := make_planet_generation(preview.seed, preview.planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	clearance := millimetres_to_position_units(PLANET_PREVIEW_WALK_CLEARANCE_MILLIMETRES)
	feet := field_surface_under(generation, metres_to_world_position(preview.camera.position), clearance)
	forward := fly_camera_forward(preview.camera)
	look := [3]i64{i64(forward.x * UNIT_VECTOR_ONE), i64(forward.y * UNIT_VECTOR_ONE), i64(forward.z * UNIT_VECTOR_ONE)}
	held, holding_foundation := preview.field.players[0].body.held_material, preview.field.players[0].body.holding_foundation
	preview.field.players[0].body = make_field_player(feet, look)
	preview.field.players[0].body.held_material = held
	preview.field.players[0].body.holding_foundation = holding_foundation
	preview.walking = true
	preview.tick_seconds = 0
	preview.pending = {}
	preview.held_now = {}
	preview.turn_remainder = {}
}

// The free camera back at the player's eye, with its own yaw and pitch.
stop_planet_preview_walk :: proc(preview: ^Planet_Preview) {
	preview.camera.position = world_position_to_metres(field_player_eye(preview.field.players[0].body, preview.field_content.tuning))
	preview.walking = false
}

// One tick of the field player on the pending input; a fly mode change
// logs as the block player's does (log_movement_toggles).
tick_planet_preview_player :: proc(preview: ^Planet_Preview) {
	before := Movement_Toggles{preview.field.players[0].body.flying, preview.field.players[0].body.no_clip}
	inputs := [1]Field_Player_Input{preview.pending}
	tick_field_simulation(&preview.field, preview.field_content, inputs[:])
	preview.tick += 1
	after := Movement_Toggles{preview.field.players[0].body.flying, preview.field.players[0].body.no_clip}
	if before.flying != after.flying {
		platform.log_printf("player: fly mode %s at tick %d", after.flying ? "on" : "off", preview.tick)
	}
	if before.no_clip != after.no_clip {
		platform.log_printf("player: no clip %s at tick %d", after.no_clip ? "on" : "off", preview.tick)
	}
	preview.pending.turn = {}
	preview.pending.just_pressed = {}
	preview.pending.held = preview.held_now
}

// The fixed step: whole ticks of the frame time, at most
// PLANET_PREVIEW_MAXIMUM_TICKS_PER_FRAME. Returns the fraction of a tick
// left over, for the camera's interpolation.
walk_planet_preview :: proc(preview: ^Planet_Preview, frame: Input_Frame, frame_seconds: f32) -> f32 {
	turn: [2]i32
	turn, preview.turn_remainder = carry_turn(preview.turn_remainder, frame_turn_angle_units(frame, frame_seconds))
	next := field_player_input_from_frame(frame, turn)
	preview.pending = merge_field_player_input(preview.pending, next)
	preview.held_now = next.held
	tick_length := 1 / f32(preview.tick_rate)
	preview.tick_seconds += frame_seconds
	for ticks := 0; preview.tick_seconds >= tick_length; ticks += 1 {
		if ticks == PLANET_PREVIEW_MAXIMUM_TICKS_PER_FRAME {
			preview.tick_seconds = 0
			break
		}
		tick_planet_preview_player(preview)
		preview.tick_seconds -= tick_length
	}
	return preview.tick_seconds / tick_length
}

// The air sample in front of the hit: the first along its normal, in half
// samples up to two samples out.
planet_preview_torch_sample :: proc(world: ^Field_World, spacing_millimetres: int, hit: Field_Raycast_Hit) -> (sample: Sample_Coordinate, found: bool) {
	half := sample_axis_to_position(1, spacing_millimetres) / 2
	for step in i64(1) ..= 4 {
		sample = nearest_field_sample(hit.position + World_Position(fixed_scale(hit.normal, step * half)), spacing_millimetres)
		if field_world_get_sample(world, sample).density <= 0 {
			return sample, true
		}
	}
	return {}, false
}

// The torch key: a torch at the air sample in front of the target, or
// none where one is.
toggle_planet_preview_torch :: proc(preview: ^Planet_Preview) {
	target := preview.field.players[0].body.target
	if !target.hit {
		return
	}
	world := &preview.field.world
	sample, found := planet_preview_torch_sample(world, preview.field.spacing_millimetres, target)
	if !found {
		return
	}
	if sample in world.light.sources {
		remove_field_light_source(world, sample)
		platform.log_printf("planet preview: torch at %v taken away", sample)
		return
	}
	add_field_light_source(world, sample, preview.torch_level)
	platform.log_printf("planet preview: torch at %v", sample)
}

// The screenshot's pit, once the player stands and the field round it has
// streamed: a sphere dug ahead of the
// feet and below them, the shadow's sky marched as the edit drain does,
// a torch at the pit's lowest air sample, and the camera tilted down into
// it. The light spreads in the following ticks.
dig_planet_preview_pit :: proc(preview: ^Planet_Preview) {
	player := &preview.field.players[0].body
	spacing := preview.field.spacing_millimetres
	world := &preview.field.world
	heading := field_heading(player.forward, player.up, player.yaw)
	ahead := World_Position(fixed_scale(heading, millimetres_to_position_units(PLANET_PREVIEW_PIT_AHEAD_MILLIMETRES)))
	down := World_Position(fixed_scale(player.up, millimetres_to_position_units(PLANET_PREVIEW_PIT_DEPTH_MILLIMETRES)))
	centre := player.position + ahead - down
	radius := millimetres_to_position_units(PLANET_PREVIEW_PIT_RADIUS_MILLIMETRES)
	edit := Field_Edit {
		mode = .Dig,
		brush = Field_Brush{shape = .Sphere, radius = radius, rate = 2 * MAXIMUM_DENSITY},
		centre = centre,
		up = player.up,
		diggable = ~bit_set[Field_Material]{},
	}
	apply_field_edit(world, spacing, edit)
	update_field_sky_after_edits(world)
	floor := centre - World_Position(fixed_scale(player.up, radius - sample_axis_to_position(1, spacing)))
	torch := nearest_field_sample(floor, spacing)
	for field_world_get_sample(world, torch).density > 0 {
		floor += World_Position(fixed_scale(player.up, sample_axis_to_position(1, spacing) / 2))
		torch = nearest_field_sample(floor, spacing)
	}
	add_field_light_source(world, torch, preview.torch_level)
	player.pitch = degrees_to_angle_units(PLANET_PREVIEW_PIT_PITCH_DEGREES)
	preview.pit_dug = true
	platform.log_printf("planet preview: pit dug, torch at %v", torch)
}

// The input of one interactive frame: the walk key switches modes, then
// the free camera flies or the player walks. Returns the interpolation
// fraction of the walk.
update_planet_preview_input :: proc(preview: ^Planet_Preview, frame_seconds: f32) -> f32 {
	if rl.IsKeyPressed(PLANET_PREVIEW_WALK_KEY) {
		if preview.walking {
			stop_planet_preview_walk(preview)
		} else {
			start_planet_preview_walk(preview)
		}
	}
	if !preview.walking {
		fly_planet_preview(preview, frame_seconds)
		return 1
	}
	if rl.IsKeyPressed(PLANET_PREVIEW_TORCH_KEY) {
		toggle_planet_preview_torch(preview)
	}
	frame := read_raylib_input_frame(preview.pressed, preview.input_bindings, {})
	preview.pressed = frame.pressed
	return walk_planet_preview(preview, frame, frame_seconds)
}

// Where the field streams from: the free camera or the player's eye.
planet_preview_viewpoint :: proc(preview: ^Planet_Preview) -> World_Position {
	if preview.walking {
		return field_player_eye(preview.field.players[0].body, preview.field_content.tuning)
	}
	return metres_to_world_position(preview.camera.position)
}

planet_preview_raylib_camera :: proc(preview: ^Planet_Preview, alpha: f32) -> rl.Camera3D {
	if preview.walking {
		view := field_player_view(preview.field.players[0].body, preview.field_content.tuning, alpha)
		return field_camera(view, preview.field.players[0].body.camera_mode, THIRD_PERSON_DISTANCE, 0, PLANET_PREVIEW_FIELD_OF_VIEW)
	}
	return fly_camera_to_raylib(preview.camera, PLANET_PREVIEW_FIELD_OF_VIEW)
}

planet_preview_height_metres :: proc(preview: ^Planet_Preview) -> f32 {
	viewpoint := world_position_to_metres(planet_preview_viewpoint(preview))
	return linalg.length(viewpoint) - f32(preview.planet.radius_metres)
}

planet_preview_mode_text :: proc(preview: ^Planet_Preview) -> string {
	switch {
	case !preview.walking:
		return "free camera"
	case preview.field.players[0].body.flying:
		return "walk mode, flying"
	case preview.field.players[0].body.on_ground:
		return "walk mode, on the ground"
	}
	return "walk mode, in the air"
}

// A material's volume held: its items and the credit, in cubic metres.
field_held_cubic_metres :: proc(miner: Field_Miner, content: Field_Simulation_Content, material: Field_Material) -> f64 {
	volume := field_place_volume_available(miner.inventory, content.materials[material].item, miner.credit[material])
	return f64(volume) / f64(FIELD_ITEM_VOLUME)
}

field_edit_refusal_text :: proc(refusal: Field_Edit_Refusal, material: Field_Material) -> string {
	name := field_material_name(material)
	switch refusal {
	case .None:
		return ""
	case .Tool_Tier:
		return fmt.tprintf("  %s needs a better pickaxe", name)
	case .Undiggable:
		return fmt.tprintf("  %s cannot be dug", name)
	case .Nothing_Held:
		return fmt.tprintf("  no %s to place", name)
	case .Would_Bury_Player:
		return "  the place would bury a player"
	case .Frame_Cell_Taken:
		return "  the foundation's cell is taken"
	case .Unknown_Frame:
		return "  the foundation's frame is gone"
	}
	return ""
}

// What the held material cycle holds now.
field_held_name :: proc(player: Field_Player) -> string {
	return player.holding_foundation ? "foundation" : field_material_name(player.held_material)
}

// The walk mode's tool line: the brush, the held material, the material
// and tint under the reticle, the volume held per material and why the
// latest edit was refused.
planet_preview_tool_text :: proc(preview: ^Planet_Preview) -> string {
	miner := preview.field.players[0]
	content := preview.field_content
	brush := content.brushes[int(miner.body.brush) % len(content.brushes)]
	target := "nothing in reach"
	if miner.body.target.hit {
		sample := field_ground_sample_at(&preview.field.world, preview.field.spacing_millimetres, miner.body.target.position)
		color := preview.planet.palette[int(sample.tint) % len(preview.planet.palette)]
		target = fmt.tprintf("%s, tint %d (%d %d %d)", field_material_name(sample.material), sample.tint, color.r, color.g, color.b)
	}
	held := ""
	for material in Field_Material {
		if content.materials[material].item != NO_ITEM {
			held = fmt.tprintf("%s  %s %.2f m3", held, field_material_name(material), field_held_cubic_metres(miner, content, material))
		}
	}
	if miner.body.frame_target.hit {
		target = fmt.tprintf("frame %d cell %v", miner.body.frame_target.frame, miner.body.frame_target.cell)
	}
	held = fmt.tprintf("%s  foundations %d, frames %d", held, inventory_count(miner.inventory, content.machines.machines[content.foundation].item) if field_foundation(content) != NO_MACHINE else 0, len(preview.field.entities.frames.frames))
	shapes := FIELD_BRUSH_SHAPE_NAMES
	return fmt.tprintf("brush %s %.1f m, holding %s  target %s %s%s", shapes[brush.shape], f64(brush.radius) / POSITION_UNITS_PER_METRE, field_held_name(miner.body), target, held, field_edit_refusal_text(miner.refusal, miner.refused_material))
}

// With capture set, the frame is saved before it is shown; saved says
// whether that worked.
draw_planet_preview :: proc(preview: ^Planet_Preview, selection: []Field_Node, capture: bool, alpha: f32) -> (saved: bool) {
	camera := planet_preview_raylib_camera(preview, alpha)
	rl.BeginDrawing()
	rl.ClearBackground(FIELD_FOG_COLOR)
	rl.BeginMode3D(camera)
	set_planet_preview_point_lights(preview, camera)
	draw_field(&preview.renderer, camera, selection)
	draw_frames(&preview.field.entities, preview.models)
	draw_planet_preview_arms(preview)
	draw_planet_preview_ghost(preview)
	rl.EndMode3D()
	height := planet_preview_height_metres(preview)
	line := fmt.ctprintf("%d fps  %s  height %.0f m  nodes %d of %d  vertices %d  chunks %d", rl.GetFPS(), planet_preview_mode_text(preview), height, preview.renderer.drawn_node_count, len(selection), preview.renderer.vertex_count, len(preview.field.world.chunks))
	rl.DrawText(line, PLANET_PREVIEW_TEXT_SIZE, PLANET_PREVIEW_TEXT_SIZE, PLANET_PREVIEW_TEXT_SIZE, rl.WHITE)
	if preview.walking {
		rl.DrawText(fmt.ctprintf("%s", planet_preview_tool_text(preview)), PLANET_PREVIEW_TEXT_SIZE, 5 * PLANET_PREVIEW_TEXT_SIZE / 2, PLANET_PREVIEW_TEXT_SIZE, rl.WHITE)
	}
	if capture {
		saved = save_planet_preview_screenshot(preview.screenshot_path)
	}
	rl.EndDrawing()
	return saved
}

// The walk screenshot waits for the pit, its light and the meshes of
// the chunks they changed: no finest node's chunk dirty and no coarser
// node waiting to mesh again.
planet_preview_pit_lit :: proc(preview: ^Planet_Preview, selection: []Field_Node) -> bool {
	world := &preview.field.world
	if !preview.field.players[0].body.on_ground || !preview.pit_dug || pending_field_light_nodes(world) > 0 || len(preview.streaming.remesh) > 0 {
		return false
	}
	for node in selection {
		if chunk := world.chunks[field_node_chunk(node)] or_else nil; node.level == 0 && chunk != nil && chunk.dirty {
			return false
		}
	}
	return true
}

// Where Place would put a foundation while one is held.
draw_planet_preview_ghost :: proc(preview: ^Planet_Preview) {
	if !preview.walking {
		return
	}
	placement, wanted := field_player_placement(preview.field.players[0].body, field_foundation(preview.field_content))
	if !wanted {
		return
	}
	if frame, cell, found := field_placement_frame(&preview.field.entities.frames, placement, preview.field_content.foundation_pitch_millimetres); found {
		draw_frame_ghost(frame, cell)
	}
}

// The walk screenshot's pad, once the player stands: a free foundation on
// the ground ahead, the square round it snapped to its frame, and a column
// of foundations on one corner.
lay_planet_preview_foundations :: proc(preview: ^Planet_Preview) {
	content := preview.field_content
	player := preview.field.players[0].body
	if preview.pad_laid || !player.on_ground || field_foundation(content) == NO_MACHINE {
		return
	}
	preview.pad_laid = true
	heading := field_player_heading(player)
	ahead := player.position + World_Position(fixed_scale(heading, millimetres_to_position_units(PLANET_PREVIEW_PAD_DISTANCE_MILLIMETRES)))
	generation := make_planet_generation(preview.seed, preview.planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	entities := &preview.field.entities
	_, frame := place_free_foundation(entities, content.machines, content.foundation, field_surface_under(generation, ahead, 0), heading, content.foundation_pitch_millimetres)
	for x in -PLANET_PREVIEW_PAD_HALF_WIDTH ..= PLANET_PREVIEW_PAD_HALF_WIDTH {
		for z in -PLANET_PREVIEW_PAD_HALF_WIDTH ..= PLANET_PREVIEW_PAD_HALF_WIDTH {
			place_on_frame(entities, content.machines, content.foundation, frame, {i32(x), 0, i32(z)}, 0)
		}
	}
	for y in 1 ..= PLANET_PREVIEW_PAD_COLUMN_HEIGHT {
		place_on_frame(entities, content.machines, content.foundation, frame, {PLANET_PREVIEW_PAD_HALF_WIDTH, i32(y), PLANET_PREVIEW_PAD_HALF_WIDTH}, 0)
	}
	platform.log_printf("planet preview: laid %d foundations on frame %d", frame_cell_count(&entities.frames, frame), frame)
	lay_planet_preview_arms(preview, frame)
}

// Returns the exit code: 0, or 1 when the screenshot could not be saved.
run_planet_preview_frames :: proc(preview: ^Planet_Preview) -> int {
	screenshot := preview.screenshot_path != ""
	for frame := 1; !rl.WindowShouldClose(); frame += 1 {
		alpha := f32(1)
		switch {
		case !screenshot:
			alpha = update_planet_preview_input(preview, rl.GetFrameTime())
		case preview.walking:
			tick_planet_preview_player(preview)
			lay_planet_preview_foundations(preview)
		}
		view := make_field_view(planet_preview_viewpoint(preview), preview.planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, preview.level_distances)
		selection := select_field_nodes(view, context.temp_allocator)
		update_field_streaming(&preview.streaming, &preview.field.world, selection)
		upload_streamed_field_meshes(&preview.renderer, &preview.streaming)
		streamed := field_streaming_settled(&preview.streaming, selection)
		// The pit waits for the chunks round it: a dig skips chunks not
		// loaded yet, which would arrive undug.
		if screenshot && preview.walking && !preview.pit_dug && streamed && preview.field.players[0].body.on_ground {
			dig_planet_preview_pit(preview)
		}
		settled := streamed && (!preview.walking || planet_preview_pit_lit(preview, selection))
		capture := screenshot && planet_preview_screenshot_due(frame, settled)
		saved := draw_planet_preview(preview, selection, capture, alpha)
		free_all(context.temp_allocator)
		if capture {
			if !saved {
				platform.log_printf("error: could not save the planet preview screenshot to %s", preview.screenshot_path)
				return 1
			}
			platform.log_printf("planet preview: saved %s after %d frames", preview.screenshot_path, frame)
			return 0
		}
	}
	return 0
}

// One player with PLANET_PREVIEW_TOOL_ITEM and
// PLANET_PREVIEW_FOUNDATION_COUNT foundations, holding the first
// placeable material.
make_planet_preview_field :: proc(items: Item_Registry, materials: Field_Material_Table, machines: Machine_Registry) -> Field_Simulation {
	field := Field_Simulation {
		spacing_millimetres = DEFAULT_SAMPLE_SPACING_MILLIMETRES,
	}
	miner := Field_Miner {
		inventory = make_inventory(PLAYER_INVENTORY_SLOT_COUNT),
	}
	miner.body.held_material = next_placeable_field_material(materials, .Air)
	if tool, found := find_item_id(items, PLANET_PREVIEW_TOOL_ITEM); found {
		inventory_add(miner.inventory, items, tool, 1)
	}
	if foundation := find_foundation_machine(machines); foundation != NO_MACHINE {
		inventory_add(miner.inventory, items, machines.machines[foundation].item, PLANET_PREVIEW_FOUNDATION_COUNT)
	}
	append(&field.players, miner)
	return field
}

// Returns the process's exit code.
// screenshot_path empty runs the interactive preview; walk starts it in
// the walk mode; daylight_percent is the sky light's share.
run_planet_preview :: proc(config: Game_Config, planets: []Planet, items: Item_Registry, machines: Machine_Registry, bindings: []Binding, data_directory: string, seed: u64, screenshot_path: string, walk: bool, daylight_percent: int) -> int {
	planet, found := find_planet(planets, PLANET_PREVIEW_PLANET)
	if !found {
		platform.log_printf("error: %s has no planet %q to preview", PLANETS_FILE_NAME, PLANET_PREVIEW_PLANET)
		return 1
	}
	tiles, tiles_problem := load_field_material_tiles(data_directory)
	if tiles_problem != "" {
		platform.log_printf("error: %s", tiles_problem)
		return 1
	}
	materials, materials_ok := load_field_material_table(data_directory, items)
	if !materials_ok {
		return 1
	}
	if daylight_percent < 0 || daylight_percent > 100 {
		platform.log_printf("error: --planet-preview-daylight=%d is outside 0 to 100", daylight_percent)
		return 1
	}
	lighting, lighting_ok := load_lighting_file(data_directory)
	if !lighting_ok {
		return 1
	}
	torch_level, torch_found := find_lighting_emitter(lighting, PLANET_PREVIEW_TORCH_EMITTER)
	if !torch_found {
		platform.log_printf("error: %s has no emitter %q", LIGHTING_FILE_NAME, PLANET_PREVIEW_TORCH_EMITTER)
		return 1
	}
	install_raylib_trace_log()
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT, .MSAA_4X_HINT})
	rl.InitWindow(PLANET_PREVIEW_WINDOW_WIDTH, PLANET_PREVIEW_WINDOW_HEIGHT, "Mine oh Belowed planet preview")
	if !rl.IsWindowReady() {
		platform.log_printf("error: could not open a window (is a display available?)")
		return 1
	}
	defer rl.CloseWindow()
	rlgl.SetClipPlanes(PLANET_PREVIEW_NEAR_METRES, f64(planet.radius_metres * PLANET_PREVIEW_FAR_RADII))
	if screenshot_path == "" {
		rl.DisableCursor()
	}
	level_distances := config.field_view.level_distances_metres
	renderer, renderer_ok := init_field_renderer(data_directory, tiles, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, f32(level_distances[FIELD_COARSEST_LEVEL]))
	if !renderer_ok {
		return 1
	}
	renderer.daylight = f32(daylight_percent) / 100
	preview := Planet_Preview {
		planet          = planet,
		level_distances = level_distances,
		camera          = planet_preview_start_camera(planet),
		field           = make_planet_preview_field(items, materials, machines),
		field_content   = Field_Simulation_Content {
			items = items,
			materials = materials,
			brushes = make_field_brushes(config.field_brushes),
			tuning = make_field_player_tuning(config.field_player, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, config.tick_rate),
			water = make_field_water_tuning(config.field_water),
			light = make_field_light_tuning(lighting, DEFAULT_SAMPLE_SPACING_MILLIMETRES),
			machines = machines,
			foundation = find_foundation_machine(machines),
			foundation_pitch_millimetres = config.foundation_pitch_millimetres,
		},
		streaming       = start_field_streaming(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, default_worker_count()),
		renderer        = renderer,
		input_bindings  = make_backend_bindings(bindings, .Raylib),
		screenshot_path = screenshot_path,
		seed            = seed,
		tick_rate       = config.tick_rate,
		torch_level     = u8(torch_level),
		models          = init_model_renderer(machines, data_directory),
		items           = items,
	}
	preview.field.world.water_planet = make_field_water_planet(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	if screenshot_path != "" {
		preview.camera = planet_preview_screenshot_camera(planet, seed, level_distances[0])
	}
	if walk {
		start_planet_preview_walk(&preview)
	}
	platform.log_printf("planet preview: %s, seed %d, radius %d m", planet.id, seed, planet.radius_metres)
	exit_code := run_planet_preview_frames(&preview)
	stop_field_streaming(&preview.streaming)
	destroy_field_renderer(&preview.renderer)
	destroy_model_renderer(&preview.models)
	destroy_field_simulation(&preview.field)
	delete(preview.field_content.brushes)
	return exit_code
}
