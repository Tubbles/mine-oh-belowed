package game

import "core:fmt"

// The placement editor and its world frame (work item 0215, doc/input.md,
// The placement editor). With the editor on (the tools radial toggles it)
// and a machine held whose footprint exceeds the direct placement limit
// (data/game.sjson), the ghost is a flat outline of the footprint centred
// on the aimed cell, and Place anchors it instead of placing. Anchored,
// the ghost stays in the world as the machine's model while the player
// walks round it: the D-pad nudges it one cell along the frame's axes
// (re-standing a new frame on the ground under the moved centre), Rotate
// turns it about its centre, Place commits it as one
// Machine_Placement_Command and Mine cancels. The editor is presentation
// state per local player: never saved, hashed or sent.

Placement_Nudge :: enum u8 {
	Away,
	Towards,
	Left,
	Right,
}

@(rodata)
PLACEMENT_NUDGE_ACTIONS := [Placement_Nudge]Action {
	.Away    = .Placement_Nudge_Away,
	.Towards = .Placement_Nudge_Towards,
	.Left    = .Placement_Nudge_Left,
	.Right   = .Placement_Nudge_Right,
}

PLACEMENT_NUDGE_ACTION_SET :: Action_Set{.Placement_Nudge_Away, .Placement_Nudge_Towards, .Placement_Nudge_Left, .Placement_Nudge_Right}

// What the world never sees while the editor is anchored: the editor's
// own controls and the ones without a meaning there (doc/input.md).
PLACEMENT_EDITOR_TAKEN_ACTIONS :: Action_Set{.Place, .Use_Item, .Mine, .Rotate_Building, .Pipette, .Drop_Stack, .Interact, .Placement_Nudge_Away, .Placement_Nudge_Towards, .Placement_Nudge_Left, .Placement_Nudge_Right}

// Per local player on its viewport, presentation only: never saved,
// hashed or sent; off at a session's start.
Placement_Editor :: struct {
	on:          bool,
	anchored:    bool,
	// What was held at the anchor; a change cancels.
	machine:     Machine_Id,
	hotbar_slot: int,
	// The anchored placement as the drain will read it: on a frame its
	// frame and origin cell, on bare ground its hit and heading with the
	// origin round cell (0, 0, 0); a foundation's anchor cell, normal,
	// size and height.
	placement:   Field_Placement,
	// The frame cell the footprint centres on ({} on bare ground).
	centre:      World_Coordinate,
	// Place after a commit, Mine after a cancel: hidden from the world
	// until released.
	guard:       Action_Set,
}

Placement_Editor_Input :: struct {
	just_pressed: Action_Set,
	pressed:      Action_Set,
	// A screen covers the world: nothing but the cancel checks runs.
	blocked:      bool,
}

Placement_Editor_Outcome :: struct {
	commit:  bool,
	command: Machine_Placement_Command,
	// Toasted when not None (placement_refusal_toast).
	refusal: Field_Edit_Refusal,
	needed:  int,
	held:    int,
}

Placement_Editor_Ghost_Kind :: enum u8 {
	Outline,
	Model,
}

Placement_Editor_Ghost :: struct {
	kind:     Placement_Editor_Ghost_Kind,
	frame:    Frame,
	machine:  Machine_Id,
	origin:   World_Coordinate,
	rotation: u8,
	// field_placement_cells, in the temp allocator.
	cells:    []World_Coordinate,
	refusal:  Field_Edit_Refusal,
}

Placement_Editor_Mode :: enum u8 {
	None,
	Outline,
	Anchored,
}

// What the HUD says of the editor (make_hud_context); the counts name a
// Too_Few_Foundations refusal.
Placement_Editor_Hud :: struct {
	mode:    Placement_Editor_Mode,
	machine: Machine_Id,
	refusal: Field_Edit_Refusal,
	needed:  int,
	held:    int,
}

// Any side of a footprint (x the width, y the height, z the depth) above
// the limit's.
placement_exceeds_direct_limit :: proc(size: [3]i32, limit: [3]i32) -> bool {
	return size.x > limit.x || size.y > limit.y || size.z > limit.z
}

// The size the limit is checked against: a foundation's block (size,
// height, size), any other machine's footprint.
placement_editor_size :: proc(player: Field_Player, machine: Machine_Id, content: Simulation_Content) -> [3]i32 {
	definition := content.machines.machines[machine]
	if definition.kind == .Foundation {
		size, height := field_foundation_block(player, content.field)
		return {size, height, size}
	}
	return definition.footprint
}

// The editor decides what Place does: anchored, or on with a held
// machine over the limit.
placement_editor_applies :: proc(editor: Placement_Editor, player: Field_Player, content: Simulation_Content) -> bool {
	if editor.anchored {
		return true
	}
	machine := field_placed_machine(player, content)
	if !editor.on || machine == NO_MACHINE {
		return false
	}
	return placement_exceeds_direct_limit(placement_editor_size(player, machine, content), content.field.direct_placement_limit)
}

// Where the outline stands: Place's placement on a frame, else on bare
// ground, as draw_field_ghosts picks; the centre is the aimed adjacent
// cell for a snapped machine, the anchor cell for a snapped foundation,
// {} on a new frame.
placement_editor_aimed :: proc(player: Field_Player, content: Simulation_Content) -> (placement: Field_Placement, centre: World_Coordinate, found: bool) {
	machine := field_placed_machine(player, content)
	if placement, found = field_player_placement(player, machine, content); found {
		switch {
		case placement.new_frame:
			centre = {}
		case content.machines.machines[machine].kind == .Foundation:
			centre = placement.cell
		case:
			centre = player.frame_target.adjacent
		}
		return
	}
	placement, found = field_bare_ground_placement(player, machine, content.machines)
	return placement, {}, found
}

// The sign of a value, +1 for zero.
placement_axis_sign :: proc(value: i64) -> i32 {
	return value < 0 ? -1 : 1
}

// One cell along the frame's horizontal axis nearest the heading (x on a
// tie), signed by it, for Away and Towards; along the other horizontal
// axis, signed by the player's right, for Left and Right. Never along the
// frame's up.
placement_nudge_step :: proc(frame: Frame, heading, right: [3]i64, nudge: Placement_Nudge) -> World_Coordinate {
	local := frame_local_direction(frame, heading)
	away_axis := abs(local.x) >= abs(local.z) ? 0 : 2
	across_axis := away_axis == 0 ? 2 : 0
	step: World_Coordinate
	switch nudge {
	case .Away:
		step[away_axis] = placement_axis_sign(local[away_axis])
	case .Towards:
		step[away_axis] = -placement_axis_sign(local[away_axis])
	case .Right:
		step[across_axis] = placement_axis_sign(frame_local_direction(frame, right)[across_axis])
	case .Left:
		step[across_axis] = -placement_axis_sign(frame_local_direction(frame, right)[across_axis])
	}
	return step
}

// The editor moved one step: a new frame re-stands on the ground under
// the moved centre (not found where no ground is in reach), a snapped
// foundation moves its anchor cell, a snapped machine its centre and so
// its origin.
nudge_placement_editor :: proc(editor: Placement_Editor, step: World_Coordinate, world: ^Field_World, spacing_millimetres, pitch_millimetres: int, machines: Machine_Registry) -> (moved: Placement_Editor, found: bool) {
	moved = editor
	placement := &moved.placement
	definition := machines.machines[placement.machine]
	switch {
	case placement.new_frame:
		origin, axes := free_frame_at(placement.hit, placement.heading, pitch_millimetres)
		frame := Frame{origin = origin, axes = axes, pitch_millimetres = pitch_millimetres}
		placement.hit = bare_ground_restand_hit(world, spacing_millimetres, frame, step) or_return
	case definition.kind == .Foundation:
		placement.cell += step
		moved.centre = placement.cell
	case:
		moved.centre += step
		placement.cell = field_footprint_origin(moved.centre, definition.footprint, placement.rotation)
	}
	return moved, true
}

// A quarter turn about the centre; a foundation's square block does not
// turn.
rotate_placement_editor :: proc(editor: Placement_Editor, machines: Machine_Registry) -> Placement_Editor {
	turned := editor
	definition := machines.machines[editor.placement.machine]
	if definition.kind == .Foundation {
		return turned
	}
	turned.placement.rotation = (editor.placement.rotation + 1) % 4
	centre := editor.placement.new_frame ? World_Coordinate{} : editor.centre
	turned.placement.cell = field_footprint_origin(centre, definition.footprint, turned.placement.rotation)
	return turned
}

// The refusal of a placement with the counts a Too_Few_Foundations one
// names (record_refused_foundation_counts).
placement_editor_refusal :: proc(state: ^Simulation_State, content: Simulation_Content, player: Player, placement: Field_Placement) -> (refusal: Field_Edit_Refusal, needed, held: int) {
	refusal = field_placement_refusal(state, content, player, placement)
	if refusal == .Too_Few_Foundations {
		needed = len(field_placement_block_cells(placement))
		held = inventory_count(player.inventory, content.machines.machines[placement.machine].item)
	}
	return
}

// One frame of the editor: a changed held machine or slot cancels;
// unanchored, Place on the outline anchors or refuses; anchored, Mine
// cancels, Place commits or refuses, Rotate turns and each nudge moves
// the ghost once. Place after a commit and Mine after a cancel stay
// guarded until released.
update_placement_editor :: proc(editor: ^Placement_Editor, state: ^Simulation_State, content: Simulation_Content, player: Player, input: Placement_Editor_Input) -> (outcome: Placement_Editor_Outcome) {
	editor.guard &= input.pressed
	if editor.anchored && (field_placed_machine(player.field, content) != editor.machine || player.selected_hotbar_slot != editor.hotbar_slot) {
		editor.anchored = false
		return
	}
	if input.blocked {
		return
	}
	if !editor.anchored {
		if .Place not_in input.just_pressed || !placement_editor_applies(editor^, player.field, content) {
			return
		}
		placement, centre, found := placement_editor_aimed(player.field, content)
		if !found {
			return
		}
		if outcome.refusal, outcome.needed, outcome.held = placement_editor_refusal(state, content, player, placement); outcome.refusal != .None {
			return
		}
		editor.anchored, editor.machine, editor.hotbar_slot = true, placement.machine, player.selected_hotbar_slot
		editor.placement, editor.centre = placement, centre
		editor.guard += {.Place}
		return
	}
	if .Mine in input.just_pressed {
		editor.anchored = false
		editor.guard += {.Mine}
		return
	}
	if .Place in input.just_pressed {
		if outcome.refusal, outcome.needed, outcome.held = placement_editor_refusal(state, content, player, editor.placement); outcome.refusal != .None {
			return
		}
		outcome.commit, outcome.command = true, machine_placement_command(editor.placement)
		editor.anchored = false
		editor.guard += {.Place}
		return
	}
	if .Rotate_Building in input.just_pressed {
		editor^ = rotate_placement_editor(editor^, content.machines)
	}
	heading, right := field_player_heading(player.field), field_player_right(player.field)
	pitch := content.field.foundation_pitch_millimetres
	for nudge in Placement_Nudge {
		if PLACEMENT_NUDGE_ACTIONS[nudge] not_in input.just_pressed {
			continue
		}
		frame, _, found := field_placement_frame(&state.world.entities.frames, editor.placement, pitch)
		if !found {
			continue
		}
		step := placement_nudge_step(frame, heading, right, nudge)
		moved, stood := nudge_placement_editor(editor^, step, &state.field.world, state.field.spacing_millimetres, pitch, content.machines)
		if !stood {
			outcome.refusal = .Too_Steep
			continue
		}
		editor^ = moved
	}
	return
}

// The pause menu's Cancel placement.
cancel_placement_editor :: proc(editor: ^Placement_Editor) {
	editor.anchored = false
}

// The tools radial's entry: flips the editor, off cancels an anchor.
// Returns the new state for the toast.
toggle_placement_editor :: proc(editor: ^Placement_Editor) -> bool {
	editor.on = !editor.on
	if !editor.on {
		editor.anchored = false
	}
	return editor.on
}

// The world's frame with the editor's controls taken: the guard and the
// nudges always, Place and Use_Item while the editor decides what Place
// does, everything of PLACEMENT_EDITOR_TAKEN_ACTIONS while anchored and
// the D-pad's hotbar meaning with its nudge.
placement_editor_world_frame :: proc(frame: Input_Frame, editor: Placement_Editor, applies: bool) -> Input_Frame {
	removed := editor.guard + PLACEMENT_NUDGE_ACTION_SET
	if applies {
		removed += {.Place, .Use_Item}
	}
	if editor.anchored {
		removed += PLACEMENT_EDITOR_TAKEN_ACTIONS
		if .Placement_Nudge_Left in frame.pressed {
			removed += {.Hotbar_Previous}
		}
		if .Placement_Nudge_Right in frame.pressed {
			removed += {.Hotbar_Next}
		}
	}
	return without_actions(frame, removed)
}

// The refusal's toast as Field_Refused shows it. In the temp allocator.
placement_refusal_toast :: proc(outcome: Placement_Editor_Outcome) -> string {
	key := field_refusal_keys[outcome.refusal]
	if key == "" {
		return ""
	}
	line := replace_message_mark(text(key), "{needed}", fmt.tprint(outcome.needed))
	return replace_message_mark(line, "{held}", fmt.tprint(outcome.held))
}

// What the viewer's ghost shows: the anchored model, else the outline
// where the editor decides what Place does, else nothing (today's
// ghosts).
placement_editor_ghost :: proc(editor: Placement_Editor, state: ^Simulation_State, content: Simulation_Content, player: Player) -> (ghost: Placement_Editor_Ghost, shown: bool) {
	placement: Field_Placement
	switch {
	case editor.anchored:
		ghost.kind, placement = .Model, editor.placement
	case placement_editor_applies(editor, player.field, content):
		found: bool
		if placement, _, found = placement_editor_aimed(player.field, content); !found {
			return {}, false
		}
		ghost.kind = .Outline
	case:
		return {}, false
	}
	frame, cell, found := field_placement_frame(&state.world.entities.frames, placement, content.field.foundation_pitch_millimetres)
	if !found {
		return {}, false
	}
	ghost.frame, ghost.machine, ghost.origin, ghost.rotation = frame, placement.machine, cell, placement.rotation
	ghost.cells = field_placement_cells(content, placement, cell)
	ghost.refusal = field_placement_refusal(state, content, player, placement)
	return ghost, true
}

// The lowest row's first and last cell: high is exclusive on x and z, so
// high - low is the outline's size.
placement_outline_box :: proc(cells: []World_Coordinate) -> (low, high: World_Coordinate) {
	if len(cells) == 0 {
		return
	}
	bottom := cells[0].y
	for cell in cells {
		bottom = min(bottom, cell.y)
	}
	low, high = {max(i32), bottom, max(i32)}, {min(i32), bottom, min(i32)}
	for cell in cells {
		if cell.y != bottom {
			continue
		}
		low.x, low.z = min(low.x, cell.x), min(low.z, cell.z)
		high.x, high.z = max(high.x, cell.x + 1), max(high.z, cell.z + 1)
	}
	return
}

// The mode the viewer's ghost shows, its machine and refusal.
placement_editor_hud :: proc(editor: Placement_Editor, state: ^Simulation_State, content: Simulation_Content, player: Player) -> Placement_Editor_Hud {
	ghost, shown := placement_editor_ghost(editor, state, content, player)
	if !shown {
		return {}
	}
	hud := Placement_Editor_Hud{mode = ghost.kind == .Model ? .Anchored : .Outline, machine = ghost.machine}
	placement := editor.placement
	if ghost.kind == .Outline {
		placement, _, _ = placement_editor_aimed(player.field, content)
	}
	hud.refusal, hud.needed, hud.held = placement_editor_refusal(state, content, player, placement)
	return hud
}

// The tool line: the refusal's text (refused), else what Place does next
// with the machine's name. In the temp allocator.
placement_editor_tool_line :: proc(hud: Placement_Editor_Hud, machines: Machine_Registry) -> (line: string, refused: bool, shown: bool) {
	if hud.mode == .None {
		return "", false, false
	}
	if hud.refusal != .None {
		return placement_refusal_toast(Placement_Editor_Outcome{refusal = hud.refusal, needed = hud.needed, held = hud.held}), true, true
	}
	key := hud.mode == .Anchored ? "field_tool_placement_anchored" : "field_tool_placement_outline"
	return replace_message_mark(text(key), "{name}", text(machines.machines[hud.machine].name_key)), false, true
}

// The glyph bar while anchored: nothing else shows.
placement_editor_glyph_hints :: proc() -> [4]Glyph_Hint {
	return {
		{.Nudge, text("hint_placement_nudge")},
		{.Rotate, text("hint_placement_rotate")},
		{.Use_Item, text("hint_placement_commit")},
		{.Mine, text("hint_placement_cancel")},
	}
}
