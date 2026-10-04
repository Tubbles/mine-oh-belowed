# 0215: The placement editor and the tools radial

Status: landed (2026-10-04, e387583; worktree `.claude/worktrees/0215` on `item/0215` from `main`, the specification approved the same day with the decisions below; the user's design after the 10 by 10 by 12 furnace landed (0212): "we need to have placement of such large machines more advanced ... start with only a ghost outline of the footprint ... center on the aimed cell, and as it is placed, the full ghost is shown, and we enter a special control state"; folds 0213)

## Goal

A 5 m machine at a 2 m reach cannot be seen whole while it is placed, and today Place puts it at the hit in one press with its corner cell on the aimed point. The player gets a placement editor: a flat footprint outline centred on the aimed cell, anchored in the world with one press, then a full ghost the player walks round and nudges, rotates, commits or cancels. The editor is a mode the player turns on and off in a new tools radial on the Pipette's button, which also becomes the home of seldom used tools and modes.

## Change

- **The tools radial.** The Pipette's bindings (gamepad D-pad Up and R5, keyboard Q, the mouse's middle button, the touch overlay's pipette control) open a radial menu (the hotbar radial's widget) while held: the entries are Pipette and Placement editor (shown with its on or off state), with room for later tools and modes; the look input steers the highlight (the right stick, the mouse, the finger), release selects, the dead centre cancels once the radial has shown. A tap (released before it shows) is Pipette as before, so the pipette stays one press.
- **The editor state.** Per local player, session state, off at a session's start, not saved. On: Place with a machine held whose footprint exceeds 2 by 2 by 3 cells (width, depth and height each at most 2, 2, 3 to be placed directly; belts, poles, pipes, chests and the small machines) starts the editor flow below. Off: a large machine is placed in one press as today, but centred on the aimed cell (the rule of 0213, folded here: an odd footprint's middle cell on the hit, an even one's centre corner; a 1 by 1 footprint unchanged). A foundation block over the threshold (5 by 5, 10 by 10) goes through the editor too when it is on.
- **The outline.** With the editor on and a large machine held, the ghost is a flat outline of the footprint on the ground (no height), centred on the aimed cell, with an arrow for the front, white, red where the placement would be refused (too steep, a cell taken, no foundation under a bottom cell) by the checks the ghost uses today (`field_placement_refusal`, `bare_ground_placement_refusal`, `frame_placement_refusal`).
- **The anchor.** Place on a white outline anchors it: the ghost becomes the machine's model, see through, standing at that spot, and the editor mode starts. Place on a red outline is refused with the reason toasted, and no mode starts.
- **The mode.** The ghost stays anchored in the world while the player walks round it with the full movement set. Each nudge moves the origin one cell along the frame's axes (on bare ground the frame re-stands on the ground under the moved centre, so the ghost follows the terrain), each rotation turns the footprint 90 degrees about its centre, and every change re-runs the refusal check and re-tints the ghost. Commit on a white ghost places the machine through the ordinary placement command carrying the origin cell and the rotation (no hit), so the simulation and the lockstep see one command as today; commit on a red ghost is refused with a toast. Cancel drops the ghost. Changing the held hotbar slot or losing the held item cancels too. The mode's state is presentation only; nothing is saved or hashed.
- **The ghost.** The full ghost draws the machine's model see through (the footprint box stays the fallback for a machine without a model), with the refused tint of the block ghost.
- **The docs.** `doc/input.md` (Bindings: the radial, the editor's table), `doc/ui.md` (the tools radial beside the hotbar radial), `doc/touch_overlay.md` (the editor's layout), `doc/architecture.md` (Placement on frames: the command carries an origin and a rotation), `doc/presentation.md` (the outline and the model ghost), `doc/content.md` (the threshold key).

## Controls

The control design (main agent, 2026-10-04), in modes:

- **World, the tools radial held.** Hold the Pipette control (D-pad Up or R5, Q, the middle mouse button, the touch pipette): the radial shows; steer with the look input; a tap (released before the radial shows) is Pipette; once the radial shows, release on an entry selects it and release in the dead centre cancels, selecting nothing. Nothing else changes while it is held.
- **World, the editor on, a large machine held.** Every control keeps its meaning; only the ghost differs (the flat outline centred on the aimed cell, with the front arrow), and Place anchors instead of placing.
- **The editor mode** (after the anchor), gamepad first:

| Control | In the editor |
| --- | --- |
| Left stick, right stick, gyro, trackpads | Move, Look, as in the world (walk round the ghost) |
| A | Jump |
| B | Sneak |
| Left stick click | Sprint |
| D-pad Up, Down | Nudge the ghost one cell away from and towards the player, along the frame axis nearest the player's facing |
| D-pad Left, Right | Nudge the ghost one cell across |
| Y (Rotate_Building), L5 | Rotate the ghost 90 degrees about its centre |
| L2 (Place) | Commit |
| R2 (Mine) | Cancel: the world's build and remove pair becomes the editor's yes and no |
| L1, R1 | Hotbar previous and next, which cancels the editor (the held machine changes) |
| X (Open_Inventory) | Opens the inventory as in the world; the ghost stays anchored and the editor resumes when the screen closes |
| Menu (Pause) | The pause menu, with a `Cancel placement` row while the editor runs (the touch fallback, as Skip arrival is) |
| View (Open_Map) | The map, as in the world |
| Keyboard and mouse | Arrows nudge, R rotates, right click commits, left click cancels, Escape opens the pause menu with its row |
| Touch | The virtual gamepad's bindings above; the overlay shows a placement layout with the four nudge buttons, rotate, commit and cancel (`serve_touch_layouts`) |

What stays unavailable in the mode: the Pipette and its radial, Drop_Stack and Interact (A is Jump alone, as a held machine never interacts). A world control never gains a second meaning while an item is held outside the mode: the editor is a mode the player entered on purpose, which is what the keybinding rule allows.

The cancel choice (user, 2026-10-04: "we need to keep sneak, so during placement editing we need to find some other way to cancel"): R2, since Place and Mine are the world's build and remove pair and Mine has no meaning while placing; the hotbar change and the pause menu row are the other two ways out.

## Verify

- Tests: the outline's centre for odd and even footprints and for 1 by 1; the threshold (2 by 2 by 3 places directly, 2 by 2 by 4 and 3 by 1 by 1 enter the editor when it is on, every size places directly with it off, centred); a red outline refuses the anchor with the reason; nudge and rotate about the centre on a frame and on bare ground (the re-stood frame follows the terrain); the refusal re-check after a nudge; commit sends the placement command with the origin and the rotation and the placed machine matches the ghost; cancel, the hotbar change and the pause row drop the ghost; the radial selects Pipette on a tap and the editor on a steered release; the editor state is not in the save or the hash; the touch layout's buttons map to the actions; the UI audit shows the editor's HUD line and the radial.
- The couch: the furnace placed where the player aims, walked round and nudged into place; a chest still placed in one press.

## Specification (design, 2026-10-04)

Everything below is read off `main` at `0eaa853`. Names in backticks that exist today were read in this session; names marked new are to be added. The block world (`entity_placement.odin`, `Placement`, `draw_placement_preview`) is not touched: the editor is the field's.

### Decisions on what the item left open

1. **The centre rule** (0213 folded): the aimed cell is the footprint's centre cell along each horizontal axis: offset `(side - 1) / 2` cells below the aimed cell, the same rule `foundation_block_first_offset` already uses for a foundation block (an even side's extra cell on the high side). So an odd side has its middle cell on the aimed cell, an even side has the aimed cell's high corner as its centre corner, a 1 by 1 and a 2 by 2 footprint are unchanged (offset 0). Why not the corner nearest the hit point: the frame target is a cell, not a point, and a sub-cell choice would make the outline jump between four positions as the reticle moves inside one cell. The height is never offset: the bottom row stands on the aimed cell's row. The rule applies to every machine Place puts on the field, editor on or off, so it is a simulation rule (`field_footprint_origin`), shared by the ghost, the direct placement and the editor.
2. **Bare ground**: the new frame keeps standing on its hit with cell (0, 0, 0) centred over it (`free_frame_at` unchanged); the machine's origin in that frame becomes `field_footprint_origin({}, footprint, rotation)` instead of (0, 0, 0), so the frame's cell (0, 0, 0) is the footprint's centre cell and "the frame re-stands on the ground under the moved centre" is literally a new hit under that cell. The simulation computes that origin itself from the machine and the rotation (it never trusts a cell from the command for a bare ground machine), so the only thing a bare ground commit carries beyond the machine and the rotation is the re-stood ground point (`hit`) and the heading the frame takes. That is the item's "(no hit)" read as "no aim": the command carries no ray, only the anchored and nudged position.
3. **The tools radial's dead centre** (settled at the approval): a tap, released with nothing highlighted before `TOOLS_RADIAL_SHOW_SECONDS` has passed, is Pipette; once the radial has shown, a release with nothing highlighted cancels (nothing selected, no press), so backing out of the radial never fires the pipette once the pipette does something (0216).
4. **Steering the radial**: the right stick past `TOOLS_RADIAL_STICK_THRESHOLD` (0.3) steers directly (as the hotbar radial's stick does); otherwise the frame's `look_delta` (mouse, right trackpad, gyro, and the touch Tools button's own drag) is gathered into a steer vector clamped to `TOOLS_RADIAL_STEER_PIXELS` (150 window pixels), so a mouse flick of a few centimetres reaches an entry and the steer stays put while the button is held. The dead centre clears the highlight (a new `Radial_Source.Held_Steered`), unlike the hotbar's held radial, so letting the stick go back to rest before releasing cancels once the radial has shown, and a tap is Pipette. While the radial is open the world gets no Look (as the hotbar radial). The radial draws only after `TOOLS_RADIAL_SHOW_SECONDS` (0.2) held or as soon as something is highlighted, so a tap does not flash it.
5. **Hold or toggle**: the tools radial is hold only; the Sneak and Sprint settings do not touch it. A tap is the whole press of Pipette's control, and Pipette reaches the world as one press on the release (`tools_radial_world_frame`), never on the press.
6. **The outline's colour**: the whole outline is white or red by the one refusal of the whole placement (`field_placement_refusal`, as today's ghost), not per cell: the refusal checks name one reason for the placement, and the toast names it.
7. **Touch**: the editor's touch controls are HUD touch buttons (the mechanism of 0134: each presses the gamepad control bound to its action through `touch_control_for_action`), not a second layout file. Why: a second layout would need a placement variant of every user layout, the latch release on a layout change, and the editor's draft path; HUD buttons follow rebinding by construction and need no file. `serve_touch_layouts` is therefore not touched. While the mode runs, the free screen's taps and holds press nothing (only drags look and the right edge's jump tap jumps): a stray tap would otherwise commit (Place) and a resting thumb cancel (Mine) a 5 m machine.
8. **The HUD in the editor**: the tool line (`draw_target_status`) says what Place does next ("Place to anchor the stone furnace" while the outline shows, "Placing the stone furnace: walk round it" while anchored), replaced by the refusal's text in the ghost's red when the placement would be refused; while anchored the glyph bar shows Move (the nudge), Turn (Rotate), Place (commit) and Cancel (Mine), and nothing else, ahead of every other glyph hint.
9. **Foundations in the editor**: a foundation block over the limit anchors, nudges and commits like a machine; Rotate does nothing to it (the block is square and `apply_foundation_block` places with rotation 0); its outline is the bounding square of the block's lowest layer.
10. **A nudge the terrain cannot take** (no ground within the bare ground probe under the moved centre) leaves the ghost where it was and toasts `field_refused_too_steep`.
11. **Nudge axes**: Away is the frame's horizontal axis (right or forward) whose direction in the frame is nearest the player's heading, with the heading's sign; Towards its opposite; Left and Right the other horizontal axis, signed by the player's right (`field_player_right`). The frame's up is never a nudge axis (a block against a wall nudges along the floor, not out of the wall).
12. **Reach**: the commit is not limited by the player's reach; the drain's checks apply as for Place.

### Controls as built (no binding beyond the Controls section)

- Four new actions, one per D-pad direction the Controls name, bound to the D-pad and the arrows they name: `Placement_Nudge_Away` (`DPAD_UP`, keyboard `UP`), `Placement_Nudge_Towards` (`DPAD_DOWN`, `DOWN`), `Placement_Nudge_Left` (`DPAD_LEFT`, `LEFT`), `Placement_Nudge_Right` (`DPAD_RIGHT`, `RIGHT`), all `context = "world"`. Commit is the existing `Place` (L2, right click), cancel the existing `Mine` (R2, left click), rotate the existing `Rotate_Building` (Y, L5, R). The tools radial is the existing `Pipette` (D-pad Up, R5, Q, middle click). No other binding changes.
- The nudge actions never reach the simulation: the world frame always drops them. Outside the mode the D-pad keeps its world meanings (Up Pipette, Down Drop_Stack, Left and Right the hotbar).
- In the mode the world frame drops `Place`, `Use_Item`, `Mine`, `Rotate_Building`, `Pipette`, `Drop_Stack`, `Interact` and the nudges; `Hotbar_Previous` is dropped only while `Placement_Nudge_Left` is held in that frame and `Hotbar_Next` only while `Placement_Nudge_Right` is (the D-pad's hotbar meaning), so L1, R1, the mouse wheel, `[`, `]` and the number keys still change the slot and cancel. A is Jump alone (Interact dropped), B Sneak, X opens the inventory or the aimed panel as in the world (`route_open_inventory_press` unchanged).
- With the editor on and a held machine over the limit, outside the mode, only `Place` and `Use_Item` are dropped (Place anchors instead). Every other control keeps its world meaning, including Rotate (which turns `placement_rotation` in the simulation, and so the outline).
- After a commit `Place`, after a cancel `Mine`, stays hidden from the world until released (`Placement_Editor.guard`), so a held R2 after Cancel does not start a pick up.

### Data

- `data/game.sjson`, after `foundation_heights`, new key with a comment naming 0215 and `doc/content.md`, Foundations: `direct_placement_limit = {width = 2, depth = 2, height = 3}`: a held machine (or a foundation's block: size, size, height) whose footprint exceeds any of the three is placed through the placement editor while it is on. Each 1 to 16 (`MAXIMUM_DIRECT_PLACEMENT_LIMIT_CELLS :: 16`, new in `data_load.odin`).
- `data_load.odin`: new `Placement_Limit_Config :: struct { width, depth, height: int }` (defined here, not `Machine_Footprint_Definition`, since content may not reference the simulation cluster); `Game_Config.direct_placement_limit: Placement_Limit_Config` after `foundation_heights`, with a comment; `direct_placement_limit_problem :: proc(limit: Placement_Limit_Config) -> string`, three `Config_Bound` lines named `direct_placement_limit.width` and so on, called from the game config check after the foundation lists.
- `field_mining.odin` `Field_Content`: `direct_placement_limit: [3]i32` (x the width, y the height, z the depth, the footprint's order), filled in `make_field_content` (`simulation_field.odin`) as `{i32(limit.width), i32(limit.height), i32(limit.depth)}`. Only the presentation reads it; the tick never does. Test configs that build a `Game_Config` by hand (`field_mining_test.odin`, `player_test.odin`, `generation_planet_test.odin`, whichever validate it) add the key where they validate.
- `data/strings/en.sjson`, new keys: `tools_radial_pipette` "Pipette"; `tools_radial_placement_editor_on` "Placement editor: on"; `tools_radial_placement_editor_off` "Placement editor: off"; `toast_placement_editor_on` "Placement editor on: large machines anchor first"; `toast_placement_editor_off` "Placement editor off"; `pause_cancel_placement` "Cancel placement"; `field_tool_placement_outline` "Place to anchor the {name}"; `field_tool_placement_anchored` "Placing the {name}: walk round it"; `hint_placement_nudge` "Move"; `hint_placement_rotate` "Turn"; `hint_placement_commit` "Place"; `hint_placement_cancel` "Cancel". The anchor and commit refusals reuse `field_refusal_keys` (with `{needed}` and `{held}` for `Too_Few_Foundations`, as `Field_Refused` toasts them).
- `data/ui/icons/`: six new placeholder icons from `tools/make_placeholder_textures.py` (new names in `UI_ICON_NAMES`, new `draw_*` functions on the round `UI_FACE` button like `draw_pause_button`): `arrow_up`, `arrow_down`, `arrow_left`, `arrow_right` (a light arrow head and shaft), `check` (an accent check mark), `cross` (a light cross). Rerun the script and commit only the six new files (the script is deterministic; any other changed file is a finding to report). `Ui_Icon` gains `Arrow_Up`, `Arrow_Down`, `Arrow_Left`, `Arrow_Right`, `Check`, `Cross` with `ui_icon_names` entries. The Tools button reuses `.Category_Tool` (the pickaxe).

### Simulation (simulation and world clusters)

`entity_frames.odin`:

- new `field_footprint_centre_offset :: proc(size: [3]i32) -> World_Coordinate`: `{(size.x - 1) / 2, 0, (size.z - 1) / 2}` of a rotated size.
- new `field_footprint_origin :: proc(centre: World_Coordinate, footprint: [3]i32, rotation: u8) -> World_Coordinate`: `centre - field_footprint_centre_offset(rotated_footprint_size(footprint, rotation))`. Comment: the centre rule of 0215 (0213).
- `field_player_placement`: signature becomes `(player: Field_Player, machine: Machine_Id, content: Simulation_Content)` (it reads `content.field` where it read `field`); the machine case's `cell` becomes `field_footprint_origin(player.frame_target.adjacent, content.machines.machines[machine].footprint, player.placement_rotation % 4)`. Foundations unchanged (`foundation_block_cells` already centres). Callers: `queue_field_player_edit` (`field_mining.odin`), `draw_field_ghosts`, `entity_frames_test.odin:508`.
- `field_bare_ground_placement`: signature `(player: Field_Player, machine: Machine_Id, machines: Machine_Registry)`; sets `cell = field_footprint_origin({}, machines.machines[machine].footprint, rotation)`. Callers: `queue_field_player_edit`, `draw_field_ghosts`, `bare_ground_line`, `simulation_field_test.odin:1122`.
- `field_placement_frame`: a `new_frame` placement returns `placement.cell` instead of `{}` (a free foundation's is `{}`; its cells come from `field_placement_block_cells` anyway).
- new, beside `Field_Placement`: `machine_placement_command :: proc(placement: Field_Placement) -> Machine_Placement_Command` (copies machine, rotation, new_frame, frame, cell, normal, hit, heading) and `field_placement_of_command :: proc(command: Machine_Placement_Command, player: Field_Player, content: Simulation_Content) -> Field_Placement`: kind `.Machine`, the command's fields, `rotation % 4`; a foundation takes `size, height = field_foundation_block(player, content.field)` (the player's own block, never the record's) and a free foundation `cell = {}`; a bare ground machine (`new_frame`, not a foundation) `cell = field_footprint_origin({}, footprint, rotation)`.
- Comment of `field_bare_ground_placement` and the file header: the footprint centred on cell (0, 0, 0), not cornered.

`machine_wear.odin`:

- `bare_ground_is_flat`: new last parameter `origin: World_Coordinate = {}`; the five probe points shift by `origin.x * pitch` and `origin.z * pitch` (`generation_planet_test.odin:472` keeps its call).
- `bare_ground_placement_refusal`: every `{}` origin becomes `placement.cell` (the flatness check's origin, `frame_drill_vein_under`, `new_frame_cells_meet_a_frame`, `placement_cells_meet_a_trunk`, `field_footprint_buries_a_player`).
- `place_on_bare_ground`: `add_entity(..., placement.cell, ...)` and `frame_drill_vein_under(record, ..., placement.cell, ...)`; comment updated.
- `bare_ground_line`: passes `content.machines` and the placement's cell to `bare_ground_is_flat`.
- new `bare_ground_restand_hit :: proc(world: ^Field_World, spacing_millimetres: int, frame: Frame, step: World_Coordinate) -> (hit: World_Position, found: bool)`: the ground under the centre of cell `(step.x, 0, step.z)` of the frame's base plane, by the probe of `bare_ground_height` at `point = {step.x * pitch + pitch / 2, step.z * pitch + pitch / 2}` (`pitch = frame_pitch_units(frame)`), returned as `origin + right * point[0] + forward * point[1] + up * height`. Called by the editor's nudge on bare ground; pure over the field.

`player_command.odin`:

- new `Machine_Placement_Command :: struct { machine: Machine_Id, rotation: u8, new_frame: bool, frame: Frame_Id, cell: World_Coordinate, normal: World_Coordinate, hit: World_Position, heading: [3]i64 }`, comment: the placement editor's commit (0215), the placement it anchored, nudged and turned; applied at the end of the tick as Place's queued placement is.
- appended last to `Player_Command` (after `Skip_Arrival_Command`, so no other tag moves).
- `apply_player_command`: `case Machine_Placement_Command: refused = !queue_machine_placement(state, content, queued.player, command)`.
- new `queue_machine_placement :: proc(state: ^Simulation_State, content: Simulation_Content, player: int, command: Machine_Placement_Command) -> bool`: false outside a field session (`!state.field.enabled`); else appends `Queued_Field_Placement{player, field_placement_of_command(command, state.players[player].field, content)}` to `state.field.placements`. The drain (`drain_field_placements`) then refuses or applies it as any placement, in order before the placements the players' ticks queue that tick, and a refusal sets `field_refusal` and toasts through `Field_Refused` as today.
- `player_command_valid`: `case Machine_Placement_Command: return index_in_range(int(value.machine), len(content.machines.machines)) && value.rotation < 4 && placement_normal_valid(value.normal) && machine_takes_placement_command(content.machines.machines[value.machine])` (the index checked first). New `placement_normal_valid :: proc(normal: World_Coordinate) -> bool` (each component -1 to 1, at most one non zero) and `machine_takes_placement_command :: proc(machine: Machine) -> bool` (an item, and a kind other than `.Belt`, `.Belt_Pole`, `.Pipe`, which are runs).
- Not saved (the list never is); no save or record layout changes, so no remap and no load log line.

`session_network.odin`: `Player_Command_Tag.Machine_Placement` appended after `Skip_Arrival` with a comment (the placement editor's commit, 0215); `encode_player_command` and `decode_player_command` cases as the others. Machines of different builds already cannot play together; the tag is new at the end, so no older tag moves.

### Input (ui cluster)

`input_actions.odin`:

- `Action`: append `Placement_Nudge_Away`, `Placement_Nudge_Towards`, `Placement_Nudge_Left`, `Placement_Nudge_Right` after `Reload_Data` with one comment (the placement editor's nudges, 0215: D-pad and arrows; never reach the simulation, `placement_editor_world_frame`). 60 actions, so `Action_Set` stays 64 bits and `Record_Input` keeps its size.
- `WORLD_ACTIONS`: add the four (a screen hides them).
- `data/bindings.sjson`: the eight lines of Controls as built, in the gamepad world block after `Hotbar_Next` and in the keyboard world block after `Hotbar_Next`, with a comment line each (the placement editor's nudges, 0215; the D-pad keeps its world meanings outside the editor). `bindings_test.odin`: `reference_raylib_buttons` (`LEFT_FACE_UP` and the other three), `reference_sdl3_buttons` (`DPAD_*`) and `reference_keys` (`UP`, `DOWN`, `LEFT`, `RIGHT`) get the pairs.
- `ui_core.odin` `Ui_Input`: `tools_radial_down: bool` (held, not an edge: Pipette's controls) and `look_delta: [2]f32`; `make_ui_input` sets `tools_radial_down = .Pipette in current.pressed`, `look_delta = current.look_delta`.
- `ui_core.odin` `Radial_Source`: new `Held_Steered` (shown while a button is held, the look input steers, the dead centre clears the highlight); `advance_radial`: `if source == .Touchpad || source == .Held_Steered || !in_centre`.
- `ui_core.odin` `Ui_State`: `tools_radial: Tools_Radial_State` after `radial`.

New file `src/ui_placement_editor.odin` (ui cluster, `ui_` prefix; references simulation and world only), header comment: the placement editor and its world frame (0215, doc/input.md, The placement editor).

```odin
Placement_Nudge :: enum u8 { Away, Towards, Left, Right }

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

Placement_Editor_Ghost_Kind :: enum u8 { Outline, Model }

Placement_Editor_Ghost :: struct {
	kind:      Placement_Editor_Ghost_Kind,
	frame:     Frame,
	machine:   Machine_Id,
	origin:    World_Coordinate,
	rotation:  u8,
	// field_placement_cells, in the temp allocator.
	cells:     []World_Coordinate,
	refusal:   Field_Edit_Refusal,
}

Placement_Editor_Mode :: enum u8 { None, Outline, Anchored }

Placement_Editor_Hud :: struct {
	mode:    Placement_Editor_Mode,
	machine: Machine_Id,
	refusal: Field_Edit_Refusal,
}
```

Procedures, each with a one line comment:

- `PLACEMENT_NUDGE_ACTIONS :: [Placement_Nudge]Action{...}` and `PLACEMENT_EDITOR_TAKEN_ACTIONS :: Action_Set{.Place, .Use_Item, .Mine, .Rotate_Building, .Pipette, .Drop_Stack, .Interact, .Placement_Nudge_Away, .Placement_Nudge_Towards, .Placement_Nudge_Left, .Placement_Nudge_Right}`.
- `placement_exceeds_direct_limit :: proc(size: [3]i32, limit: [3]i32) -> bool`: any of x, y, z above the limit's (both in the footprint's order).
- `placement_editor_size :: proc(player: Field_Player, machine: Machine_Id, content: Simulation_Content) -> [3]i32`: a foundation's block `{size, height, size}` (`field_foundation_block`), any other machine's footprint.
- `placement_editor_applies :: proc(editor: Placement_Editor, player: Field_Player, content: Simulation_Content) -> bool`: anchored, or on with `field_placed_machine` not `NO_MACHINE` and its size over `content.field.direct_placement_limit`. Called by the world frame, the ghost and the HUD.
- `placement_editor_aimed :: proc(player: Field_Player, content: Simulation_Content) -> (placement: Field_Placement, centre: World_Coordinate, found: bool)`: `field_player_placement`, else `field_bare_ground_placement`, as `draw_field_ghosts` picks today; the centre is `frame_target.adjacent` for a snapped machine, `placement.cell` for a snapped foundation, `{}` for a new frame.
- `placement_nudge_step :: proc(frame: Frame, heading, right: [3]i64, nudge: Placement_Nudge) -> World_Coordinate`: decision 11; `frame_local_direction` of the heading, the larger of `|x|` and `|z|` (x on a tie) gives Away's axis and sign; Left and Right take the other axis, signed by the dot of `right` with that frame axis (Right positive along `right`).
- `nudge_placement_editor :: proc(editor: Placement_Editor, step: World_Coordinate, world: ^Field_World, spacing_millimetres, pitch_millimetres: int, machines: Machine_Registry) -> (moved: Placement_Editor, found: bool)`: a new frame re-stands (`free_frame_at(placement.hit, placement.heading, pitch)`, then `bare_ground_restand_hit`; not found keeps the editor); a snapped foundation moves its anchor cell; a snapped machine moves `centre` and recomputes `placement.cell = field_footprint_origin(centre, footprint, rotation)`.
- `rotate_placement_editor :: proc(editor: Placement_Editor, machines: Machine_Registry) -> Placement_Editor`: a foundation unchanged; else rotation + 1 mod 4 and the origin recomputed about the same centre (`centre` on a frame, `{}` on bare ground).
- `update_placement_editor :: proc(editor: ^Placement_Editor, state: ^Simulation_State, content: Simulation_Content, player: Player, input: Placement_Editor_Input) -> Placement_Editor_Outcome`, in this order: `guard &= input.pressed`; anchored and (`field_placed_machine(player.field, content) != editor.machine` or `player.selected_hotbar_slot != editor.hotbar_slot`) cancels silently; blocked returns; not anchored: with `placement_editor_applies` and `.Place` just pressed, `placement_editor_aimed` found, `field_placement_refusal(state, content, player, placement)` refuses with the outcome's refusal (counts as `record_refused_foundation_counts` takes them: block cells and held foundations) or anchors (machine, slot, placement, centre; `guard += {.Place}`); anchored: `.Mine` just pressed cancels (`guard += {.Mine}`) and stops; `.Place` just pressed checks the refusal, refuses or commits (`commit = true`, `command = machine_placement_command(placement)`, `anchored = false`, `guard += {.Place}`) and stops; `.Rotate_Building` rotates; each nudge action just pressed nudges once in the enum's order (a failed re-stand returns `refusal = .Too_Steep`). The heading and right come from `field_player_heading` and `field_player_right` of `player.field`; the field world and spacing from `state.field`; the pitch from `content.field.foundation_pitch_millimetres`.
- `cancel_placement_editor :: proc(editor: ^Placement_Editor)`: anchored false. Called by the pause row.
- `toggle_placement_editor :: proc(editor: ^Placement_Editor) -> bool`: flips `on`, off cancels; returns the new state for the toast. Called by the tools radial.
- `placement_editor_world_frame :: proc(frame: Input_Frame, editor: Placement_Editor, applies: bool) -> Input_Frame`: `without_actions` of the guard and the four nudges always; `.Place` and `.Use_Item` when `applies`; `PLACEMENT_EDITOR_TAKEN_ACTIONS` when anchored, plus `.Hotbar_Previous` when `.Placement_Nudge_Left in frame.pressed` and `.Hotbar_Next` when `.Placement_Nudge_Right in frame.pressed`.
- `placement_refusal_toast :: proc(outcome: Placement_Editor_Outcome) -> string`: the `field_refusal_keys` text with `{needed}` and `{held}` replaced, as `Field_Refused` does (in the temp allocator).
- `placement_editor_ghost :: proc(editor: Placement_Editor, state: ^Simulation_State, content: Simulation_Content, player: Player) -> (ghost: Placement_Editor_Ghost, shown: bool)`: anchored gives `.Model` of `editor.placement`; else `placement_editor_applies` and `placement_editor_aimed` found give `.Outline`; else not shown. Frame and cell from `field_placement_frame`, cells from `field_placement_cells`, refusal from `field_placement_refusal`.
- `placement_outline_box :: proc(cells: []World_Coordinate) -> (low, high: World_Coordinate)`: the lowest row's minimum and maximum cell (`high` exclusive on x and z, so `high - low` is the outline's size).
- `placement_editor_hud :: proc(editor: Placement_Editor, state: ^Simulation_State, content: Simulation_Content, player: Player) -> Placement_Editor_Hud`: the mode the ghost shows, its machine and refusal.
- `placement_editor_tool_line :: proc(hud: Placement_Editor_Hud, machines: Machine_Registry) -> (line: string, refused: bool, shown: bool)`: the refusal's `field_refusal_keys` text (refused), else `field_tool_placement_outline` or `field_tool_placement_anchored` with `{name}` the machine's `text(name_key)`.
- `placement_editor_glyph_hints :: proc() -> [4]Glyph_Hint`: `{.Nudge, hint_placement_nudge}`, `{.Rotate, hint_placement_rotate}`, `{.Use_Item, hint_placement_commit}`, `{.Mine, hint_placement_cancel}`.

### The tools radial (ui cluster, `hud.odin` beside `hotbar_radial`)

```odin
Tools_Radial_Entry :: enum u8 { Pipette, Placement_Editor }

Tools_Radial_State :: struct {
	radial:           Radial_State,
	// Look pixels gathered since it opened, within TOOLS_RADIAL_STEER_PIXELS.
	steer:            [2]f32,
	held_seconds:     f32,
	// Released on Pipette: the frame loop gives the next world frame one
	// Pipette press (tools_radial_world_frame) and clears it.
	pipette_selected: bool,
}
```

Constants: `TOOLS_RADIAL_STEER_PIXELS :: 150`, `TOOLS_RADIAL_STICK_THRESHOLD :: 0.3`, `TOOLS_RADIAL_SHOW_SECONDS :: 0.2`, `TOOLS_RADIAL_ENTRY_WIDTH :: 5 * UI_ROW_HEIGHT`; the entries sit at `radial_slot_offset(index, len(Tools_Radial_Entry)) * HUD_RADIAL_RADIUS` round the screen centre (Pipette at the top, the editor at the bottom).

- `tools_radial_steer :: proc(steer, look_delta: [2]f32) -> [2]f32`: added and clamped to the steer radius.
- `tools_radial_position :: proc(right_stick, steer: [2]f32) -> [2]f32`: `stick_to_pad_position(right_stick)` past the stick threshold, else `0.5 + steer / (2 * TOOLS_RADIAL_STEER_PIXELS)` (pad coordinates, y down as the look delta).
- `tools_radial :: proc(state: ^Ui_State, editor: ^Placement_Editor)`: touching is `state.input.tools_radial_down` and not (`editor != nil && editor.anchored`) and not `state.radial.open`; gathers the steer and the held time while open (resets both when it opens); `advance_radial(..., .Held_Steered, len(Tools_Radial_Entry))`; on close, `Placement_Editor` with `editor != nil` toggles and toasts `toast_placement_editor_on` or `_off`; the Pipette entry sets `pipette_selected`; nothing highlighted (-1) sets it only when `held_seconds < TOOLS_RADIAL_SHOW_SECONDS` (a tap) and otherwise selects nothing. Draws while open and (`held_seconds >= TOOLS_RADIAL_SHOW_SECONDS` or a highlight).
- `draw_tools_radial :: proc(state: ^Ui_State, editor_on: bool)`: each entry a `TOOLS_RADIAL_ENTRY_WIDTH` by `UI_ROW_HEIGHT` box in `UI_PANEL_COLOR`, outlined as `draw_hotbar_radial` outlines (accent and `UI_FOCUS_BORDER` when highlighted), its label fitted (`draw_text_fitted`, centred): `tools_radial_pipette`, `tools_radial_placement_editor_on` or `_off`.
- `tools_radial_world_frame :: proc(frame: Input_Frame, tools: Tools_Radial_State) -> Input_Frame`: drops `.Pipette` (held and edge), drops Look while `tools.radial.open`, adds `.Pipette` to `just_pressed` when `tools.pipette_selected`.
- `draw_hud`: where it resets `state.radial = {}` under an open screen, `state.tools_radial = {}` too; after `hotbar_radial(...)`, `tools_radial(state, screen_context.placement_editor)`.

### The HUD (`hud.odin`)

- `Hud_Context.placement: Placement_Editor_Hud` (comment: the viewport's editor as its ghost shows it, 0215; zero shows nothing).
- `draw_hud`: after the bare ground and foundation lines are taken, `if line, refused, shown := placement_editor_tool_line(hud.placement, screen_context.machines); shown { tool_status = line }`, drawn with `GHOST_INVALID_COLOR`'s red as a `Ui_Color` when refused (a new `HUD_REFUSED_TEXT_COLOR :: Ui_Color{230, 60, 50, 255}`). Before the schematic hints (after `touch_row_shows`): `if hud.placement.mode == .Anchored { hints := placement_editor_glyph_hints(); ui_glyph_bar(state, hints[:]); return }`.
- `Glyph_Button` (`ui_widgets.odin`): new `Rotate` (`glyph_button_actions` `.Rotate_Building`) and `Nudge` (`.Placement_Nudge_Away`, whose first gamepad control is D-pad Up and key Up).
- `Hud_Touch_Button`: becomes `Inventory, Map, Pause, Tools, Rotate, Nudge_Away, Nudge_Towards, Nudge_Left, Nudge_Right, Commit, Cancel`; actions `.Tools = .Pipette`, nudges their actions, `.Commit = .Place`, `.Cancel = .Mine`; icons `.Tools = .Category_Tool`, arrows, `.Commit = .Check`, `.Cancel = .Cross`.
- `hud_touch_buttons_shown :: proc(rotates, editing: bool) -> bit_set[Hud_Touch_Button]`: editing gives Inventory, Map, Pause, Rotate and the six editor buttons (no Tools, Pipette is unavailable in the mode); otherwise Inventory, Map, Pause, Tools, and Rotate while it acts.
- `hud_touch_button_rectangles`: the row (Inventory to Rotate) as today by index; the editor's buttons a 3 by 3 grid of `UI_SLOT_SIZE` boxes on a `UI_SLOT_SIZE + UI_GAP` step whose middle column's centre is `area.x + area.width - 2 * step` and whose bottom row's bottom edge is `3 * UI_GAP` above the row's top: top row Commit, Nudge_Away, Cancel (L2 left, R2 right as on the pad); middle row Nudge_Left, empty, Nudge_Right; bottom row empty, Nudge_Towards, empty.

### Touch overlay (`touch_overlay.odin`)

- `Touch_Overlay_Context.placement_editing: bool` (the first viewport's editor is anchored), set in `touch_overlay_context` (`loop.odin`); `frame_hud_touch_buttons_shown` passes it to `hud_touch_buttons_shown`.
- `Touch_Hud_Button.steers: bool` (true for Tools, set in `frame_hud_touch_buttons`); `hud_touch_button_at` returns it beside the control; `Touch_Slot.hud_steers` keeps it from the landing; `touch_overlay_output` adds `slot.position - slot.previous` to `output.look_delta` for such a slot (render pixels, converted with the rest by `read_touch_overlay_frame`), so the Tools finger's drag steers the radial while the world's Look is held off by the radial.
- `Touch_Interaction_Frame.placement_editing: bool` (from the context in `touch_interaction_frame`); `touch_overlay_output` takes it as a new last parameter `placement_editing := false`: a `Hold` slot presses and aims nothing, and `add_touch_tap_output` presses and aims nothing for a tap that does not jump.

### The frame loop (`loop.odin`, `viewport.odin`, `loop_field_session.odin`)

- `Viewport_Interaction.placement_editor: Placement_Editor` (comment: 0215, per local player, never saved). `enter_session` sets `viewport.interaction.placement_editor = {}`; a new or removed viewport starts from zero already.
- new `update_viewport_placement_editor :: proc(state: ^Frame_State, viewport: ^Viewport)`: outside a field session or before the player's entry, `anchored = false` and return; else reads `lockstep_view_player` (the ghost's player), builds the input from `viewport.interaction.input` less `viewport.interaction.world_action_guard` with `blocked = viewport_world_blocked(viewport^)`, runs `update_placement_editor` against `&state.session.simulation` and `frame_simulation_content(state)`, queues `outcome.command` with `queue_player_command(&session.simulation.player_commands, viewport.player, ...)` on a commit and toasts `placement_refusal_toast(outcome)` on `viewport.interaction.ui` on a refusal. Called in `update_frame_world` after `assign_waiting_players`, for every active viewport, before `update_session`.
- `viewport_world_input`: after `world_input`, `frame = tools_radial_world_frame(frame, viewport.interaction.ui.tools_radial)`; in a field session with the player ready, `frame = placement_editor_world_frame(frame, editor, placement_editor_applies(editor, view.field, content))` (signature gains nothing: it already has `state`).
- `update_frame_world`: after `update_session`, `viewport.interaction.ui.tools_radial.pipette_selected = false` for every active viewport.
- `make_screen_context`: `screen_context.placement_editor = &viewport.interaction.placement_editor` in a field session, nil otherwise. `Screen_Context.placement_editor: ^Placement_Editor` (comment: the viewport's editor, 0215; nil outside a field and in tests that run none).
- `make_hud_context`: `hud.placement = placement_editor_hud(viewport.interaction.placement_editor, &session.simulation, frame_simulation_content(state), view_player)` in a field session.
- `Field_Scene.placement_editor: Placement_Editor` (zero draws today's ghosts), set in the viewport's scene (`loop_field_session.odin:357`); the planet preview leaves it zero.
- `draw_field_ghosts`: after the run ghost, `if ghost, shown := placement_editor_ghost(scene.placement_editor, scene.state, scene.content, player); shown { draw_placement_editor_ghost(scene, ghost); return }`, else today's path.
- new `draw_placement_editor_ghost :: proc(scene: Field_Scene, ghost: Placement_Editor_Ghost)` (`loop_field_session.odin`): `.Outline` draws `draw_footprint_outline` of `placement_outline_box(ghost.cells)` with the arrow for a machine (none for a foundation block); `.Model` draws `draw_frame_ghost_model` and, when it returns false, `draw_frame_ghost` per cell; colour `frame_ghost_color(ghost.refusal)` for the model, `placement_outline_color(ghost.refusal)` for the outline.

### Presentation

- `render_frames.odin`: `PLACEMENT_OUTLINE_COLOR :: rl.Color{240, 240, 240, 220}`, `PLACEMENT_OUTLINE_REFUSED_COLOR :: rl.Color{230, 60, 50, 220}`, `PLACEMENT_OUTLINE_LIFT_CELLS :: 0.02`, `PLACEMENT_OUTLINE_WIDTH_CELLS :: 0.1`; `placement_outline_color :: proc(refusal: Field_Edit_Refusal) -> rl.Color`; `machine_front_direction :: proc(rotation: u8) -> [3]f32`: the model's +x front turned as `model_transform` turns it, `{1,0,0}`, `{0,0,1}`, `{-1,0,0}`, `{0,0,-1}` for 0 to 3; `draw_footprint_outline :: proc(frame: Frame, low, high: World_Coordinate, rotation: u8, arrow: bool, color: rl.Color)`: under the frame's matrix (as `draw_frame_ghost` pushes it), four flat strips `PLACEMENT_OUTLINE_WIDTH_CELLS` wide and 0.04 cells high along the edges of the rectangle `low` to `high` at height `low.y + PLACEMENT_OUTLINE_LIFT_CELLS`, inside it, and, with `arrow`, `draw_ghost_chevron(ghost_chevron_triangles(centre - front * length / 2, centre + front * length / 2, {front.z, 0, -front.x}), color)` with `length = 0.6 * min(size.x, size.z)`. Static: nothing pulses (DESIGN.md, No perceivable repetition).
- `render_models.odin`: `draw_frame_ghost_model :: proc(renderer: Model_Renderer, machines: Machine_Registry, frame: Frame, machine: Machine_Id, origin: World_Coordinate, rotation: u8, tint: rl.Color) -> bool`: false for an arm machine (`machine_arm_model` found) or one without a model; else the body at `frame_render_matrix(frame) * model_transform(origin, rotated_footprint_size(footprint, rotation), rotation)` and the part at `body * motion_transform(machine.motion, machine.footprint, 0)`, both with `ghost_layer_colors(tint)`, between `rlgl.DisableDepthMask()` and `rlgl.EnableDepthMask()` so the far side shows through the near side (see through).

### The pause row (`ui_screens.odin`)

- `pause_world_buttons`: first, before Skip arrival: `if screen_context.placement_editor != nil && screen_context.placement_editor.anchored`, a button `text("pause_cancel_placement")`; pressed, `cancel_placement_editor(screen_context.placement_editor)` and `state.screens.count = 0` (the menu closes, as Skip arrival's does), then `cut_top(content, UI_GAP)`. A split screen guest's menu shows its own editor's row.

### Tests

New file `src/ui_placement_editor_test.odin` unless named otherwise; the field fixtures are `make_field_placement_test`, `lay_test_pad`, `stand_test_player_on_cell` and `aim_test_player_at_cell` (`entity_frames_test.odin`) and `start_field_test_session` (`simulation_field_test.odin`); machines from the shipped data (`make_test_machines`): `stone_furnace` 10 by 10 by 12, `assembler_1` 3 by 3 by 2, `boiler` 3 by 2 by 2, `steel_furnace` 2 by 2 by 2, `wood_gasifier` 2 by 2 by 3, `big_pole` 1 by 1 by 6, `wooden_chest` 1 by 1 by 1.

1. `test_a_footprint_centres_on_the_aimed_cell` (`entity_frames_test.odin`): `field_footprint_origin` with centre (5, 0, 5): 1 by 1 gives (5, 0, 5); 2 by 2 (5, 0, 5); 3 by 3 (4, 0, 4); 5 by 5 (3, 0, 3); 10 by 10 (1, 0, 1); 3 by 2 at rotation 0 (4, 0, 5) and at rotation 1 (5, 0, 4); the y never moves.
2. `test_a_large_machine_placed_directly_centres_on_the_aimed_cell` (`entity_frames_test.odin`): a pad of 7 by 7 cells, the player aiming at its middle top face (adjacent (3, 0, 3)): Place with `assembler_1` held stands it at origin (2, 0, 2); with `steel_furnace` at (3, 0, 3); with `wooden_chest` at (3, 0, 3) (through the tick, no editor involved).
3. `test_a_machine_on_bare_ground_stands_centred_on_its_frame` (`simulation_field_test.odin`, the bare ground test's fixture): the existing `test_a_machine_placed_on_bare_ground_stands_or_is_too_steep` updated to the new signature and to the furnace's origin (-4, 0, -4) on its new frame; the flatness probe covers the centred footprint (a new assert: `bare_ground_is_flat` with the origin agrees with the refusal).
4. `test_the_direct_placement_limit_sends_large_machines_to_the_editor`: with limit {2, 3, 2}: (2, 3, 2) is direct; (2, 4, 2) and (3, 1, 1) and (1, 1, 3) exceed. `placement_editor_applies` with the editor on: `wood_gasifier` false, `big_pole` and `assembler_1` true, a held foundation with size index of 5 and height 1 true, size 2 height 2 false; with it off every one false.
5. `test_place_anchors_with_the_editor_on_and_places_directly_with_it_off`: on a pad, `assembler_1` held, editor on: a frame with Place just pressed anchors (`anchored`, `placement.cell` (2, 0, 2) for adjacent (3, 0, 3)), the outcome commits nothing, and `placement_editor_world_frame` drops Place and Use_Item; the same with `wood_gasifier` does not anchor and keeps Place; editor off with `assembler_1` keeps Place.
6. `test_a_red_outline_refuses_the_anchor_with_the_reason`: `assembler_1` aimed so a footprint cell meets a taken cell (a chest placed at (2, 0, 3) first): Place leaves the editor unanchored with `refusal == .Frame_Cell_Taken`; a held 5 by 5 foundation block with one foundation held gives `.Too_Few_Foundations` with `needed` 25 and `held` 1, and `placement_refusal_toast` names both numbers.
7. `test_nudge_and_rotate_turn_the_ghost_about_its_centre_on_a_frame`: anchored `boiler` at centre (3, 0, 3) rotation 0 (origin (2, 0, 3)): with the heading along the frame's +z, Away moves the centre to (3, 0, 4), Towards back, Right to (4, 0, 3) or (2, 0, 3) as `field_player_right` signs it (asserted against the dot of the right with the frame's right axis); Rotate gives rotation 1 and origin (3, 0, 2) about the same centre; four rotations return to the start. `placement_nudge_step` alone: headings along +x, -x, +z, -z and a 30 degree heading between +z and +x (Away +z) give the expected steps.
8. `test_a_bare_ground_nudge_restands_the_frame_on_the_terrain`: `make_test_field(Test_Terrain{kind = .Slope, slope_degrees = 5}, 1000)` (rising along +x, `player_field_test.odin`), a free placement of `steel_furnace` anchored on it with the heading along +x: after Away, the new hit lies one pitch along the old frame's Away axis (within a sample, measured across the up), its height along the up is higher than the old hit's by the slope's rise over one pitch (within a sample), and `bare_ground_height` of the re-stood frame at its cell (0, 0, 0) centre is within one sample of zero. On `Test_Terrain{kind = .Flat}` the height does not change.
9. `test_a_nudge_rechecks_the_refusal`: anchored white `assembler_1` next to a chest: a nudge onto the chest makes `field_placement_refusal` `.Frame_Cell_Taken` (the ghost's refusal), Place then refuses with that reason and queues nothing; a nudge back makes it white and Place commits.
10. `test_commit_queues_one_placement_and_the_machine_matches_the_ghost`: on a pad (frame) and on bare ground, anchor, nudge twice, rotate once, Place: one `Machine_Placement_Command` on `player_commands` with the editor's cell and rotation (bare ground: its hit and heading); after the tick the machine's entity has the ghost's origin and rotation, `common_cells` equal `placement_editor_ghost`'s cells, one item is spent, and the editor is back to the outline with `guard` holding Place.
11. `test_cancel_the_hotbar_and_the_pause_row_drop_the_ghost`: Mine cancels and keeps Mine out of the world frame until released (the next frame with Mine held drops it, the frame after its release passes a new Mine); a changed `selected_hotbar_slot` cancels; the held stack emptied (machine changes) cancels; `cancel_placement_editor` cancels. In the mode a frame with D-pad Left (Placement_Nudge_Left and Hotbar_Previous pressed) drops Hotbar_Previous, one with L1 alone (Hotbar_Previous only) keeps it.
12. `test_the_world_frame_hides_the_editors_controls`: `placement_editor_world_frame` in the mode drops every action of `PLACEMENT_EDITOR_TAKEN_ACTIONS` and keeps Jump, Sneak, Sprint, Open_Inventory, Open_Map, Pause, Hotbar_Next from R1, Move and Look; outside the mode with the editor on and a large machine only Place and Use_Item go; with the editor off only the nudges go. `tools_radial_world_frame` drops Pipette always, adds it once when `pipette_selected`, drops Look while open.
13. `test_the_placement_editor_leaves_the_save_and_the_hash_alone`: a field placement fixture; `simulation_state_hash` and the save bytes (`write_frame_tables` and the entities body the save test helpers write) taken before; anchor, nudge, rotate and an editor toggle; both unchanged; the commit changes nothing until the tick runs the command.
14. `test_a_machine_placement_command_round_trips_and_is_validated` (`player_command_test.odin`): `encode_player_command` then `decode_player_command` gives the same value; `player_command_valid` refuses a machine index past the table, rotation 4, a normal (1, 1, 0), and a belt machine; accepts the furnace; applied in a block world session it is refused (`Action_Refused`).
15. `test_two_sessions_committing_a_placement_hash_the_same` (`lockstep_test.odin` or beside `test_two_sessions_placing_one_foundation_block_hash_the_same`): one session queues a `Machine_Placement_Command`, the other receives the record; both place the furnace at the same tick with the same hash.
16. `test_the_tools_radial_selects_pipette_on_a_tap_and_the_editor_on_a_steered_release` (`hud_test.odin`, driving `tools_radial` with a `Ui_State` and hand built `Ui_Input`): two frames down without steering then up: `pipette_selected`, the editor unchanged, nothing drawn on the first frame (show delay); down with `look_delta` (0, 200) then up: the editor toggles on with a toast and no Pipette; down with the right stick (0, -1) then up: toggles back off; down, steered, the stick and steer back to rest (the steer reset is not possible with the mouse, so this case uses the stick alone) then up after the show delay: nothing selected, no Pipette and the editor unchanged (the shown radial's dead centre cancels); with the editor anchored the radial does not open; with the hotbar radial open it does not open.
17. `test_the_pause_menu_offers_cancel_placement_while_the_editor_runs` (`ui_pointer_test.odin`, beside the Skip arrival test): with an anchored editor the menu has `pause_button_id("pause_cancel_placement")`, activating it cancels the editor and empties the stack; unanchored, or with a nil editor, there is no such button.
18. `test_the_placement_touch_buttons_press_the_editor_actions` (`touch_overlay_test.odin`): `hud_touch_buttons_shown(false, false)` is Inventory, Map, Pause, Tools; `(true, false)` adds Rotate; `(true, true)` is Inventory, Map, Pause, Rotate and the six editor buttons. With the shipped bindings each editor button's control (`touch_control_for_action`) is `DPAD_UP`, `DPAD_DOWN`, `DPAD_LEFT`, `DPAD_RIGHT`, `LEFT_TRIGGER`, `RIGHT_TRIGGER`, and the Tools button's `DPAD_UP`. The existing assertions at `touch_overlay_test.odin:1631` move to the new signature.
19. `test_the_tools_button_drag_steers_the_radial` (`touch_overlay_test.odin`): a finger landing on the Tools button and moving 60 render pixels presses `DPAD_UP` and adds 60 pixels to `output.look_delta`; a finger on the Map button that moves adds nothing.
20. `test_taps_and_holds_press_nothing_while_the_placement_editor_runs` (`touch_overlay_test.odin`): with `placement_editing` a tap on free screen presses no trigger and sets no aim, a hold presses no `RIGHT_TRIGGER`, a tap in the jump zone still jumps; without it both press as today.
21. `test_no_touch_overlay_element_covers_a_hotbar_slot` (existing): extended so the editor's buttons at every `UI_AUDIT_SIZES` size overlap no hotbar slot, no row button and each other, and lie inside the safe area.
22. UI audit cases (`ui_audit_test.odin`; `Ui_Audit_Case` gains `tools_radial: bool`, which feeds `{tools_radial_down = true, look_delta = {0, TOOLS_RADIAL_STEER_PIXELS}}`, and `placement: Placement_Editor_Mode`, which sets `Hud_Context.placement` with the furnace and points `Screen_Context.placement_editor` at an audit owned editor anchored when the mode is Anchored): "hud tools radial", "hud placement outline", "hud placement outline refused" (the refusal Too_Steep, the longest tool line), "hud placement editor" (the glyph bar), "hud placement editor touch" (`touch = true`, `touch_hud_buttons = hud_touch_buttons_shown(true, true)`), "pause, placement editor" (screens Pause with the row). Every size and text scale, as the matrix runs; no existing case is made obsolete.
23. `test_entering_a_session_turns_the_placement_editor_off` (`viewport_test.odin`): `make_viewport_test_frame`, the first viewport's editor set on and anchored, a second session entered (`start_session` and `enter_session` as the fixture does, the first left with `leave_session`): the editor is zero; in that block world session `update_viewport_placement_editor` keeps it unanchored and `viewport_world_input` keeps Place.
24. `test_direct_placement_limit_is_range_checked` (`data_load_test.odin`): the shipped config loads with {2, 2, 3}; a width 0 and a height 17 are refused naming `direct_placement_limit.width` and `.height`.
25. `test_the_machine_front_turns_with_the_rotation` (`render_ghost_test.odin`): `machine_front_direction` for 0 to 3, and it agrees with `model_transform`'s image of +x.
26. `bindings_test.odin`: the reference tables as in Input.
27. `test_a_nudge_over_no_ground_keeps_the_ghost_and_toasts_too_steep` (added in the fix round, decision 10): a steel furnace anchored on bare ground a quarter metre from the rim of a 10 m deep pit (`Test_Terrain` Hole), heading into it: Away finds no ground in the probe's reach, so the editor stays anchored with its placement unchanged, the outcome's refusal is Too_Steep and its toast is `field_refused_too_steep`'s text.

### Docs (same commit, one place per fact)

- `doc/input.md`, Bindings, Gamepad: the D-pad row becomes "Left, right: hotbar previous and next. Up: the tools radial held, Pipette tapped. Down: Drop_Stack"; L5, R5 "Rotate_Building, the tools radial (Pipette)". Keyboard and mouse: Q and the middle button hold the tools radial; the arrows nudge in the placement editor. New subsection "### The placement editor" after Keyboard and mouse: the three modes of the Controls section, the editor's table (copied from the item's Controls, keyboard and touch rows included), what is dropped and why, the guard after a commit or a cancel, the tools radial's steering (stick, gathered look pixels, the Tools button's drag; the dead centre is Pipette). Hold or toggle: one line, the tools radial is hold only and the two settings do not touch it.
- `doc/ui.md`, Principles: the radial line gains the tools radial (shown while Pipette's control is held, the look input steers, release selects, the dead centre is Pipette, not a cancel). Other screens (the pause menu): the Cancel placement row while the editor runs.
- `doc/hud.md`, Targeting: the editor's tool line and its red refusal, the bare ground ghost centred (the line "at cell (0, 0, 0)" corrected), the outline and the model ghost; Layout or the glyph paragraph: the editor's four hints; the HUD touch buttons: Tools and the editor's grid.
- `doc/touch_overlay.md`, Hotbar and HUD buttons: the Tools button (presses Pipette's control, its drag steers), the editor's buttons and their grid, taps and holds pressing nothing in the mode; Taps, holds and aiming: the same exception in one line.
- `doc/architecture.md`, Simulation, Placement on frames: the centre rule; a bare ground machine centred on cell (0, 0, 0); the placement editor's commit as `Machine_Placement_Command` queued into `Field_Simulation.placements` at the tick's start and drained with the rest; the editor is presentation state per viewport, never saved or hashed. Window and prediction: the editor's outline and ghost read the predicted player as the ghost does.
- `doc/presentation.md`, The field session: the viewer's ghosts gain the editor's outline (flat, white or red, the front arrow) and the anchored model ghost (see through, the box fallback).
- `doc/content.md`, Foundations or Machines on bare ground: the `direct_placement_limit` key with its bounds, and the centring of every placed footprint.
- `doc/code_map.md`, ui: `ui_placement_editor.odin` in the file list ("the placement editor's state, its world frame and its ghost, 0215"); the field counts it names (`Ui_State`, `Screen_Context`, `Viewport_Interaction`) bumped; the Reaches into record unchanged (the loop calls the ui procedures with the predicted player, so ui gains no edge into loop). Run `python3 tools/code_graph.py --check doc/code_map.md`.
- `doc/log/<landing date>.md`, "## The placement editor and the tools radial (0215)", tags `placement, editor, input, bindings, touch, hud, lockstep, m14`: the centre rule and why the low middle cell; bare ground centred on its frame and its origin the simulation's own; the command (why a command and not the input record: the editor's state is presentation, so the commit carries the result); no save change, a new network tag at the end; Pipette has no effect today and reaches the world on release; touch through HUD buttons and the free screen's gestures off in the mode; the threshold in data.

### Hand-back check lines that apply

- Memory a frame draws from: the editor and the tools radial are plain values; the pause row and the radial write `bool` and enum fields during the UI pass and free nothing, so no request is needed. Satisfied by construction; say so in the report.
- A number parsed from text is range checked: `direct_placement_limit` (1 to 16 each, test 24); the command's machine index, rotation and normal (test 14).
- A changed save layout: none (test 13 shows the editor is outside the save and the hash; the command list is not saved).
- A long string fitted, a growing list capped, at the smallest audit size: the tool line through `draw_target_status` (fitted by the audit's long furnace name and the refusal), the radial's labels through `draw_text_fitted`, the editor's touch grid inside the safe area at every size (tests 21 and 22).
- A UI audit case made obsolete: none; six new cases.
- Tests never touch the state directory: none of these write files.
- Not applicable: file writes, start-up fallbacks beyond the existing game config path, shared budgets.

### Questions for the main agent

1. `Pipette` has no effect anywhere in `src/` today (the action, its bindings and the reference tests only). "A tap is Pipette as before" therefore does nothing on a tap, before and after; the specification routes the press to the world on the release so a later Pipette item finds it there. Is a Pipette implementation wanted, as a work item of its own?
2. Touch: HUD buttons instead of a placement layout through `serve_touch_layouts`, and the free screen's taps and holds off while the mode runs (decision 7). Approve, or should the editor be a layout file?
3. The six new icons from the placeholder generator: acceptable as placeholders, or should the nudge buttons reuse an existing icon (only `.Dpad` fits, and it does not show a direction)?
4. The centre rule moves the direct placement of every footprint with a side of 3 or more (assemblers, boilers, the 3 by 3 drill, the refinery, the launch pad, the furnace) for everyone, editor on or off, as 0213 asked. Confirm that the block world keeps its corner placement (it is not in the item).

### Decisions at the approval (main agent, 2026-10-04)

1. The pipette does nothing today: the tap keeps routing one `Pipette` press to the world as specified, and the pipette itself is work item `0216-the-pipette.md`, after this one.
2. The touch controls as HUD touch buttons (each pressing the gamepad control bound to its action through `touch_control_for_action`, the mechanism of 0134) are approved; no layout file. The free screen's taps and holds pressing nothing while the mode runs is approved too.
3. The six placeholder icons from `tools/make_placeholder_textures.py` and the pickaxe for the Tools button are approved; the art pass comes with the machines.
4. The block world keeps its corner placement: the centre rule is the field's, as the specification says.
5. The tools radial's dead centre is settled as decision 3 above: a tap is Pipette, the shown radial's dead centre cancels. The Controls section and the Change section now say the same.
