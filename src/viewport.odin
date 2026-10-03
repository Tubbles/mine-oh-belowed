package game

import rl "shared:raylib"

// Split screen (work item 0178): one simulation, up to four local players,
// each with a viewport holding its player, its input device, its rectangle
// of the window, the per player halves of the interaction and presentation
// groups (its input, UI, screens, session views, camera and per frame
// memories) and the requests its screens made. Frame_State keeps the
// viewports beside the process wide groups. Single player is one viewport
// covering the window, drawn straight to it as before.
//
// Devices: the first viewport reads the keyboard, the mouse and the touch
// overlay, and takes the first gamepad no viewport owns as soon as it has
// none. Every other viewport reads its own gamepad. Start (the Pause action)
// on a gamepad no viewport owns first gives that gamepad to a viewport
// whose pad was disconnected, else adds a viewport and a local player
// through the add player path of a join (request_local_player). A viewport
// whose pad disconnects keeps its player and shows a notice until a pad
// takes it again or its pause menu removes it (Remove_Viewport).

MAXIMUM_VIEWPORTS :: 4

// Render pixels of the window.
Pixel_Rectangle :: struct {
	x, y, width, height: int,
}

// The per player half of the input and UI group (Frame_Interaction keeps
// the devices, the fonts, the title and the touch overlay).
Viewport_Interaction :: struct {
	input:              Input_Frame,
	previous_input:     Input_Frame,
	// The rumble for this frame, for the viewport's pad.
	haptic:             Haptic_Request,
	// World actions still held since a screen closed, see update_world_action_guard.
	world_action_guard: Action_Set,
	ui:                 Ui_State,
	// The player's browsers, statistics and map (ui_session_views.odin),
	// made with the session or the viewport and destroyed with either.
	session_views:      Session_Views,
	// The HUD's biome banner, rendering state across frames.
	biome_banner:       Biome_Banner,
	// The map's texture (ui_draw.odin), per viewport since each map view
	// counts its own revisions.
	ui_images:          Ui_Image_Cache,
}

// The per player half of the presentation group: what depends on the
// camera. The renderers, the atlases and the sound stay process wide
// (Frame_Presentation), so a sound plays once.
Viewport_Presentation :: struct {
	// The camera the world was last drawn with: the touch overlay's aim
	// ray (touch_aim_direction) and the HUD's mining ring.
	camera:           rl.Camera3D,
	// The sprint field of view kick's progress, 0 to 1 (advance_sprint_kick).
	sprint_kick:      f32,
	// The frame's cues (work item 0162, cues.odin) of the viewport's
	// player, reset with the session.
	cue_memory:       Cue_Memory,
	// Particles and feedback (work item 0067), render state only.
	particles:        Particle_System,
	particle_memory:  Particle_Memory,
	// The player's body animation (work item 0066).
	player_animation: Player_Animation_Memory,
	// Split screen only: the world and the UI drawn at the viewport's size
	// (begin_viewport_target), then onto its rectangle.
	target:           rl.RenderTexture2D,
}

Viewport :: struct {
	// The player's index in the simulation's players; NO_PLAYER while a
	// joined machine waits for the host's answer (Local_Player_Added).
	player:         int,
	// The SDL gamepad (its JoystickID) the viewport reads, 0 for none.
	gamepad:        u32,
	// The keyboard, the mouse and the touch overlay: the first viewport.
	keyboard_mouse: bool,
	// Its gamepad disconnected: the notice shows until a pad takes it.
	pad_lost:       bool,
	rectangle:      Pixel_Rectangle,
	// Frame input to tick input (Tick_Input_Accumulator), reset with the
	// session.
	tick_input:     Tick_Input_Accumulator,
	// A field session's turn fraction in angle units, carried from one
	// stamped record to the next (carry_field_turn), reset with the session.
	field_turn_remainder: [2]f32,
	// What its screens asked for (Screen_Context.requests). The game's
	// requests (GLOBAL_FRAME_REQUESTS) move to Frame_State.requests after
	// the UI pass (collect_global_requests); the rest serve this viewport.
	requests:       Frame_Requests,
	interaction:    Viewport_Interaction,
	presentation:   Viewport_Presentation,
}

// The requests that belong to the game rather than a screen: served once
// a frame however many viewports asked.
GLOBAL_FRAME_REQUESTS :: Frame_Requests{.Reload_Data, .Quit}

// The viewports' rectangles in the window: one covers it, two split it
// stacked or side by side (the split_screen setting), three and four take
// its quarters (the fourth quarter stays empty with three).
viewport_rectangles :: proc(count: int, screen: [2]int, layout: Split_Screen_Layout) -> (rectangles: [MAXIMUM_VIEWPORTS]Pixel_Rectangle) {
	half := screen / 2
	rest := screen - half
	switch {
	case count <= 1:
		rectangles[0] = {0, 0, screen.x, screen.y}
	case count == 2 && layout == .Stacked:
		rectangles[0] = {0, 0, screen.x, half.y}
		rectangles[1] = {0, half.y, screen.x, rest.y}
	case count == 2:
		rectangles[0] = {0, 0, half.x, screen.y}
		rectangles[1] = {half.x, 0, rest.x, screen.y}
	case:
		rectangles[0] = {0, 0, half.x, half.y}
		rectangles[1] = {half.x, 0, rest.x, half.y}
		rectangles[2] = {0, half.y, half.x, rest.y}
		rectangles[3] = {half.x, half.y, rest.x, rest.y}
	}
	return rectangles
}

// The UI follows the screen's height (ui_pixels_per_unit). In split screen
// a viewport narrower than 16:9 (two side by side) scales its UI down
// until the 16:9 layout fits its width, so every screen keeps the room it
// has at full screen; one viewport keeps the setting as it is.
viewport_ui_scale :: proc(ui_scale: f32, rectangle: Pixel_Rectangle, count: int) -> f32 {
	if count <= 1 || rectangle.height <= 0 {
		return ui_scale
	}
	aspect := f32(rectangle.width) / f32(rectangle.height)
	return ui_scale * min(1, aspect / (16.0 / 9.0))
}

Pad_Claim :: enum u8 {
	None,
	// The gamepad becomes the viewport's.
	Take,
	// A new viewport with a new local player reads the gamepad.
	Add,
}

// What a gamepad no viewport owns does with this frame's just pressed
// actions. Start (the Pause action) takes a guest viewport whose pad was
// lost first. Otherwise the first viewport without a pad takes it at once
// (as the one pad of single player always did), but not while a guest
// waits, so a replugged guest pad is never taken silently. Otherwise
// Start adds a viewport while a world is played and there is room. So
// the keyboard and one pad are one player: the first viewport takes the
// first pad.
pad_claim :: proc(viewports: []Viewport, just_pressed: Action_Set, world_played: bool) -> (claim: Pad_Claim, index: int) {
	if len(viewports) == 0 {
		return .None, -1
	}
	start := .Pause in just_pressed
	guest_waits := false
	for viewport, viewport_index in viewports[1:] {
		if viewport.pad_lost && start {
			return .Take, viewport_index + 1
		}
		guest_waits ||= viewport.pad_lost
	}
	switch {
	case viewports[0].gamepad == 0 && (start || !guest_waits):
		return .Take, 0
	case start && world_played && len(viewports) < MAXIMUM_VIEWPORTS:
		return .Add, len(viewports)
	}
	return .None, -1
}

// The pad is a viewport's.
pad_owned :: proc(viewports: []Viewport, gamepad: u32) -> bool {
	for viewport in viewports {
		if viewport.gamepad == gamepad {
			return true
		}
	}
	return false
}

// A disconnected pad leaves its viewport waiting; the player stays.
lose_viewport_pad :: proc(viewports: []Viewport, gamepad: u32) {
	for &viewport in viewports {
		if viewport.gamepad == gamepad {
			viewport.gamepad = 0
			viewport.pad_lost = true
		}
	}
}

// The viewport shows the lost pad notice: a split screen viewport whose
// pad disconnected.
viewport_waits_for_pad :: proc(viewport: Viewport, count: int) -> bool {
	return count > 1 && viewport.pad_lost
}

// The viewport's player has its entry: a local player that joined
// later has none before its join tick.
viewport_player_ready :: proc(session: ^Session, viewport: Viewport) -> bool {
	return session != nil && viewport.player >= 0 && viewport.player < len(session.simulation.players)
}

// The viewports in use.
active_viewports :: proc(state: ^Frame_State) -> []Viewport {
	return state.viewports[:state.viewport_count]
}

// The first viewport's UI: the toasts of the game (saves, reloads, the
// network) and the title.
primary_ui :: proc(state: ^Frame_State) -> ^Ui_State {
	return &state.viewports[0].interaction.ui
}

// A viewport for the player on the pad, its UI set up like the first's
// (theme, fonts, bindings).
make_viewport :: proc(player: int, gamepad: u32, template: ^Ui_State) -> Viewport {
	viewport := Viewport {
		player  = player,
		gamepad = gamepad,
	}
	ui := &viewport.interaction.ui
	ui.theme, ui.fonts, ui.measure_text = template.theme, template.fonts, template.measure_text
	ui.bindings, ui.input_backend = template.bindings, template.input_backend
	viewport.interaction.session_views = make_session_views()
	return viewport
}

destroy_viewport :: proc(viewport: ^Viewport) {
	destroy_ui_state(&viewport.interaction.ui)
	destroy_session_views(&viewport.interaction.session_views)
	release_ui_images(&viewport.interaction.ui_images)
	release_viewport_target(&viewport.presentation)
	viewport^ = {}
}

// A pad's Start in a played world: a new local player (offline and on the
// host at once, a joined machine once the host answers) and its viewport.
// The press is held over, so the new viewport does not see it as a fresh
// Pause. False without room.
add_viewport :: proc(state: ^Frame_State, gamepad: u32, held: Action_Set) -> bool {
	if state.session == nil || state.viewport_count >= MAXIMUM_VIEWPORTS {
		return false
	}
	player := request_local_player(state.session)
	viewport := make_viewport(player, gamepad, primary_ui(state))
	viewport.interaction.input.pressed = held
	state.viewports[state.viewport_count] = viewport
	state.viewport_count += 1
	return true
}

// Between frames (its pause menu's Remove_Viewport): the player leaves the
// session from its next tick and keeps its entry; the viewport's UI goes.
// The first viewport is the machine's own and stays.
remove_viewport :: proc(state: ^Frame_State, index: int) {
	if index <= 0 || index >= state.viewport_count {
		return
	}
	switch {
	case state.session == nil:
	case state.viewports[index].player == NO_PLAYER:
		cancel_local_player_request(state.session)
	case:
		leave_local_player(state.session, state.viewports[index].player)
	}
	destroy_viewport(&state.viewports[index])
	for after in index + 1 ..< state.viewport_count {
		state.viewports[after - 1] = state.viewports[after]
	}
	state.viewports[state.viewport_count - 1] = {}
	state.viewport_count -= 1
}

// Every viewport but the first, when the world ends.
remove_extra_viewports :: proc(state: ^Frame_State) {
	for index in 1 ..< state.viewport_count {
		destroy_viewport(&state.viewports[index])
	}
	state.viewport_count = min(state.viewport_count, 1)
}

// A joined machine's new local players (Local_Player_Added) go to the
// viewports waiting for one, in order.
assign_waiting_players :: proc(state: ^Frame_State) {
	lockstep := &state.session.lockstep
	for local in lockstep.locals {
		owned := false
		for viewport in active_viewports(state) {
			owned ||= viewport.player == local.player
		}
		if owned {
			continue
		}
		for &viewport in active_viewports(state) {
			if viewport.player == NO_PLAYER {
				viewport.player = local.player
				break
			}
		}
	}
}

// After the UI pass: the game's requests of every viewport into the
// frame's set, so each serves once.
collect_global_requests :: proc(state: ^Frame_State) {
	for &viewport in active_viewports(state) {
		state.requests += viewport.requests & GLOBAL_FRAME_REQUESTS
		viewport.requests -= GLOBAL_FRAME_REQUESTS
	}
}

// The viewports' rectangles for this frame's window.
place_viewports :: proc(state: ^Frame_State, screen: [2]int) {
	rectangles := viewport_rectangles(state.viewport_count, screen, state.settings.split_screen)
	for &viewport, index in active_viewports(state) {
		viewport.rectangle = rectangles[index]
	}
}

// The viewport's target at its size, made again when the size changed.
prepare_viewport_target :: proc(presentation: ^Viewport_Presentation, rectangle: Pixel_Rectangle) {
	target := presentation.target
	if target.id != 0 && int(target.texture.width) == rectangle.width && int(target.texture.height) == rectangle.height {
		return
	}
	release_viewport_target(presentation)
	presentation.target = rl.LoadRenderTexture(i32(max(rectangle.width, 1)), i32(max(rectangle.height, 1)))
}

release_viewport_target :: proc(presentation: ^Viewport_Presentation) {
	if presentation.target.id != 0 {
		rl.UnloadRenderTexture(presentation.target)
	}
	presentation.target = {}
}

// The target onto its rectangle; a render texture is stored upside down.
draw_viewport_target :: proc(viewport: Viewport) {
	texture := viewport.presentation.target.texture
	source := rl.Rectangle{0, 0, f32(texture.width), -f32(texture.height)}
	rectangle := viewport.rectangle
	destination := rl.Rectangle{f32(rectangle.x), f32(rectangle.y), f32(rectangle.width), f32(rectangle.height)}
	rl.DrawTexturePro(texture, source, destination, {}, 0, rl.WHITE)
}
