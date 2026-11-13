package game

import "core:fmt"
import "core:slice"
import "core:testing"

// Glyph buttons of a hint list.
hint_buttons :: proc(hints: []Glyph_Hint) -> []Glyph_Button {
	buttons := make([]Glyph_Button, len(hints), context.temp_allocator)
	for hint, index in hints {
		buttons[index] = hint.button
	}
	return buttons
}

// Work item 0197: aimed at a trunk the glyph bar's Mine says Fell, with
// the inventory glyph and Pause; without a trunk no Fell hint. The Fell
// hint is the one the bar keeps (0219).
@(test)
test_the_fell_hint_shows_on_an_aimed_tree :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	world: World
	defer destroy_world(&world)
	player := Player{target = {entity = NO_ENTITY}, inventory = make_inventory(HOTBAR_SLOT_COUNT, context.temp_allocator)}
	screen_context := Screen_Context{world = &world, player = &player}
	hud := Hud_Context{field_view_set = true}
	testing.expect(t, !field_fell_hint_shown(screen_context, hud))
	hints, kept := world_glyph_hints(screen_context, hud)
	testing.expect(t, !slice.contains(hint_buttons(hints), Glyph_Button.Mine))
	testing.expect_value(t, kept, 0)
	hud.field_view.tree_target = {hit = true, key = {1, 2, 3}, distance = POSITION_UNITS_PER_METRE}
	testing.expect(t, field_fell_hint_shown(screen_context, hud))
	hints, kept = world_glyph_hints(screen_context, hud)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Mine, .Inventory, .Pause}), "Fell, Inventory, Pause")
	testing.expect_value(t, hints[0].label, "Fell")
	testing.expect_value(t, kept, 1)
}

// Work item 0219: Place for every tool but the hand and a shovel, pickaxe
// or axe (0265), Turn for a machine or a vessel part (0361) alone, Brush for a material, the hand,
// a shovel, pickaxe or axe or a bucket (0295); outside a field session a held
// furnace adds no held hints.
@(test)
test_the_held_hints_follow_the_tool :: proc(t: ^testing.T) {
	for tool in Field_Held_Tool {
		testing.expectf(t, field_held_tool_places(tool) == (tool != .Hand && tool != .Tool), "%v places", tool)
		testing.expectf(t, field_held_tool_turns(tool) == (tool == .Machine || tool == .Vessel_Part), "%v turns", tool)
		testing.expectf(t, field_held_tool_cycles_brush(tool) == (tool == .Material || tool == .Hand || tool == .Tool || tool == .Water || tool == .Drain), "%v cycles the brush", tool)
	}
	use_shipped_strings()
	defer thread_string_table = nil
	world: World
	defer destroy_world(&world)
	items := make_test_items()
	player := Player{target = {entity = NO_ENTITY}, inventory = make_inventory(HOTBAR_SLOT_COUNT, context.temp_allocator)}
	hold_test_stack(&player, Item_Stack{test_item(items, "stone_furnace"), 1})
	screen_context := Screen_Context{world = &world, player = &player, items = items}
	hud := Hud_Context{field_view_set = true}
	hud.field_view.tool = .Machine
	hints, kept := world_glyph_hints(screen_context, hud)
	buttons := hint_buttons(hints)
	for button in ([3]Glyph_Button{.Use_Item, .Tools, .Rotate}) {
		testing.expectf(t, !slice.contains(buttons, button), "%v outside a field session", button)
	}
	testing.expect_value(t, kept, 0)
	hud.field_session = true
	hints, kept = world_glyph_hints(screen_context, hud)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Use_Item, .Tools, .Rotate, .Inventory, .Pause}), "Place, Tools, Turn, Inventory, Pause")
	testing.expect_value(t, kept, 3)
	hud.field_view.tool = .Material
	hints, kept = world_glyph_hints(screen_context, hud)
	testing.expect_value(t, hints[2].label, "Brush")
	testing.expect_value(t, kept, 3)
	// In the tech demo the control is the torchlight's (0297).
	screen_context.content.field.tech_demo = true
	hints, kept = world_glyph_hints(screen_context, hud)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Use_Item, .Torchlight, .Rotate, .Inventory, .Pause}), "Place, Torch, Brush, Inventory, Pause")
	testing.expect_value(t, hints[1].label, "Torch")
	testing.expect_value(t, kept, 3)
}

// The tools radial (0215): a tap is Pipette and draws nothing; a steered
// release toggles the editor with a toast; the shown radial's dead centre
// selects nothing; it does not open while the editor is anchored or the
// hotbar radial is open.
@(test)
test_the_tools_radial_selects_pipette_on_a_tap_and_the_editor_on_a_steered_release :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	state: Ui_State
	defer destroy_ui_state(&state)
	editor: Placement_Editor
	frame :: proc(state: ^Ui_State, editor: ^Placement_Editor, input: Ui_Input, seconds: f32 = 1.0 / 60) {
		test_ui_frame(state, input, seconds)
		tools_radial(state, editor)
	}
	frame(&state, &editor, {tools_radial_down = true})
	testing.expect(t, state.tools_radial.radial.open)
	testing.expect_value(t, len(state.draw_list), 0)
	frame(&state, &editor, {tools_radial_down = true})
	frame(&state, &editor, {})
	testing.expect(t, state.tools_radial.pipette_selected)
	testing.expect(t, !editor.on)
	state.tools_radial.pipette_selected = false

	frame(&state, &editor, {tools_radial_down = true, look_delta = {0, 200}})
	testing.expect_value(t, state.tools_radial.radial.highlight, int(Tools_Radial_Entry.Placement_Editor))
	testing.expect(t, len(state.draw_list) > 0)
	frame(&state, &editor, {})
	testing.expect(t, editor.on)
	testing.expect(t, !state.tools_radial.pipette_selected)
	testing.expect_value(t, len(state.toasts), 1)

	frame(&state, &editor, {tools_radial_down = true, right_stick = {0, -1}})
	frame(&state, &editor, {})
	testing.expect(t, !editor.on)
	testing.expect(t, !state.tools_radial.pipette_selected)

	frame(&state, &editor, {tools_radial_down = true, right_stick = {0, -1}})
	testing.expect_value(t, state.tools_radial.radial.highlight, int(Tools_Radial_Entry.Placement_Editor))
	frame(&state, &editor, {tools_radial_down = true}, TOOLS_RADIAL_SHOW_SECONDS + 0.1)
	testing.expect_value(t, state.tools_radial.radial.highlight, -1)
	testing.expect(t, len(state.draw_list) > 0)
	frame(&state, &editor, {})
	testing.expect(t, !state.tools_radial.pipette_selected)
	testing.expect(t, !editor.on)

	editor.anchored = true
	frame(&state, &editor, {tools_radial_down = true})
	testing.expect(t, !state.tools_radial.radial.open)
	frame(&state, &editor, {})
	editor.anchored = false
	state.radial = {open = true, highlight = -1}
	frame(&state, &editor, {tools_radial_down = true})
	testing.expect(t, !state.tools_radial.radial.open)
}

// Work item 0231: the pod's hatch takes no Interact, so the glyph bar
// offers nothing on one, shut or open.
@(test) // slow
test_the_glyph_bar_offers_nothing_on_a_hatch :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	stage_cached_field_set(state)
	pod, frame, found := find_test_pod(&state.world.entities, content.machines)
	testing.expect(t, found)
	if !found {
		return
	}
	machine := content.machines.machines[pod.machine]
	state.players[0].field = test_airlock_player(frame, machine)
	inner_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, 1)
	inner := entity_at(&state.world.entities, inner_origin, frame.id)
	outer_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, 0)
	outer := entity_at(&state.world.entities, outer_origin, frame.id)
	aim := proc(state: ^Simulation_State, frame: Frame_Id, handle: Entity_Handle) {
		state.players[0].field.frame_target = Frame_Raycast_Hit{hit = true, frame = frame, occupant = {handle = entity_occupant_handle(handle)}}
	}
	aimed_hints := proc(state: ^Simulation_State, content: Simulation_Content) -> []Glyph_Hint {
		screen_context := Screen_Context{content = content, world = &state.world, player = &state.players[0], tick = state.tick}
		return aimed_glyph_hints(screen_context, Hud_Context{})
	}
	aim(state, frame.id, outer)
	testing.expect(t, !hatch_is_open(&state.world.entities, outer))
	testing.expectf(t, len(aimed_hints(state, simulation_content)) == 0, "the shut outer door offers %v", aimed_hints(state, simulation_content))
	testing.expect(t, toggle_hatch(&state.world.entities, content.machines, inner, state.tick, nil))
	aim(state, frame.id, inner)
	testing.expectf(t, len(aimed_hints(state, simulation_content)) == 0, "the open inner door offers %v", aimed_hints(state, simulation_content))
}

// Work item 0233: on the gamepad Interact and Inventory share X, so on a
// power switch the bar shows Turn alone and on a full schematic crate
// Take alone; with separate controls (the keyboard's F and E) Open or
// Inventory shows beside them. A furnace shows Open on X either way. The
// switch and the furnace have items, so Pipette shows on the Tools glyph
// (0216); a crate has none.
@(test)
test_x_shows_one_hint_on_a_switch_and_a_crate :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	switch_handle := add_entity(&world.entities, content.machines, test_machine(content.machines, "power_switch"), {4, 1, 4}, 0)
	furnace := add_entity(&world.entities, content.machines, test_machine(content.machines, "steel_furnace"), {8, 1, 4}, 0)
	player := make_test_player(content.blocks, {4.5, 1, 1.5})
	player.target = Raycast_Hit{hit = true, block = {4, 1, 4}, entity = switch_handle}
	screen_context := Screen_Context{content = content, world = &world, player = &player}
	hints, _ := world_glyph_hints(screen_context, {}, true)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Interact, .Tools, .Pause}), "Turn, Pipette, Pause")
	testing.expect_value(t, hints[0].label, "Turn")
	testing.expect_value(t, hints[1].label, "Pipette")
	hints, _ = world_glyph_hints(screen_context, {}, false)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Interact, .Inventory, .Tools, .Pause}), "Turn, Open, Pipette, Pause")
	testing.expect_value(t, hints[1].label, "Open")
	player.target = Raycast_Hit{hit = true, block = {8, 1, 4}, entity = furnace}
	hints, _ = world_glyph_hints(screen_context, {}, true)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Inventory, .Tools, .Pause}), "Open, Pipette, Pause")
	testing.expect_value(t, hints[0].label, "Open")

	crate_world := make_drill_world(content)
	records := make_test_records(content)
	sites := [1]Crate_Site{{region = {0, 0}, position = {4, 1, 4}, choice = 3}}
	register_crate_sites(&records.crate_sites, sites[:])
	place_pending_crates(world_tick_context(&crate_world, &records, content, TEST_TICK_RATE))
	crate := entity_at(&crate_world.entities, {4, 1, 4})
	player.target = Raycast_Hit{hit = true, block = {4, 1, 4}, entity = crate}
	crate_context := Screen_Context{content = content, world = &crate_world, player = &player}
	hints, _ = world_glyph_hints(crate_context, {}, true)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Interact, .Pause}), "Take, Pause")
	hints, _ = world_glyph_hints(crate_context, {}, false)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Interact, .Inventory, .Pause}), "Take, Inventory, Pause")
	testing.expect_value(t, hints[1].label, "Inventory")
	// An empty crate takes no Interact: X opens the inventory there.
	pool_get(&crate_world.entities.schematic_crates, crate).slots[0] = EMPTY_STACK
	hints, _ = world_glyph_hints(crate_context, {}, true)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Inventory, .Pause}), "Inventory, Pause")
}

// Work item 0216: Pipette shows on the Tools glyph, in the held Tools
// hint's place or after Open with nothing held, while a tap would pick
// something (where the bar has room for it,
// test_the_pipette_hint_gives_way_at_every_size): a placed
// thing with an item, an aimed cable; not the pod, nothing aimed, during
// a run, seated, in the tech demo or during the fall.
@(test)
test_the_pipette_hint_names_what_a_tap_picks :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	world: World
	defer destroy_world(&world)
	machines := make_test_machines()
	items := make_test_items()
	chest := add_entity(&world.entities, machines, test_machine(machines, "wooden_chest"), {4, 1, 4}, 0)
	place_test_pod(&world.entities, machines)
	pod, _, _ := find_pod(&world.entities, machines)
	furnace := Item_Stack{test_item(items, "stone_furnace"), 1}
	player := Player{target = {entity = NO_ENTITY}, inventory = make_inventory(HOTBAR_SLOT_COUNT, context.temp_allocator)}
	hold_test_stack(&player, furnace)
	screen_context := Screen_Context{world = &world, player = &player, items = items, machines = machines}
	hud := Hud_Context{field_view_set = true, field_session = true}
	hud.field_view.tool = .Machine
	hints, kept := world_glyph_hints(screen_context, hud)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Use_Item, .Tools, .Rotate, .Inventory, .Pause}), "nothing aimed: Place, Tools, Turn, Inventory, Pause")

	frame_hit :: proc(handle: Entity_Handle) -> Frame_Raycast_Hit {
		return Frame_Raycast_Hit{hit = true, occupant = {handle = entity_occupant_handle(handle)}}
	}
	hud.field_view.frame_target = frame_hit(chest)
	testing.expect_value(t, hud_pipette_item(screen_context, hud), machines.machines[test_machine(machines, "wooden_chest")].item)
	hints, kept = world_glyph_hints(screen_context, hud)
	testing.expectf(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Mine, .Inventory, .Use_Item, .Tools, .Rotate, .Pause}), "the chest: Pick up, Open, Place, Pipette, Turn, Pause, not %v", hint_buttons(hints))
	testing.expect_value(t, kept, 5)
	testing.expect(t, slice.equal(hint_labels_on(hints, .Tools), []string{"Pipette"}), "Pipette in the Tools hint's place")
	hold_test_stack(&player, EMPTY_STACK)
	hints, kept = world_glyph_hints(screen_context, hud)
	testing.expectf(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Mine, .Inventory, .Tools, .Pause}), "nothing held: Pick up, Open, Pipette, Pause, not %v", hint_buttons(hints))
	testing.expect_value(t, kept, 3)
	hold_test_stack(&player, furnace)

	hud.field_view.frame_target = frame_hit(pod.handle)
	testing.expect_value(t, hud_pipette_item(screen_context, hud), NO_ITEM)
	hints, _ = world_glyph_hints(screen_context, hud)
	testing.expect(t, slice.equal(hint_labels_on(hints, .Tools), []string{"Tools"}), "the pod: Tools back among the held hints")

	hud.field_view.frame_target = frame_hit(chest)
	no_pipette :: proc(t: ^testing.T, screen_context: Screen_Context, hud: Hud_Context, name: string) -> []Glyph_Hint {
		testing.expectf(t, hud_pipette_item(screen_context, hud) == NO_ITEM, "%s picks nothing", name)
		hints, _ := world_glyph_hints(screen_context, hud)
		testing.expectf(t, !slice.contains(hint_labels_on(hints, .Tools), "Pipette"), "%s shows no Pipette", name)
		return hints
	}
	run := hud
	run.field_view.cable_run = true
	run.field_view.tool = .Cable
	hints = no_pipette(t, screen_context, run, "a run")
	testing.expect(t, slice.equal(hint_labels_on(hints, .Use_Item), []string{"Connect"}), "the run's Connect")
	testing.expect(t, slice.equal(hint_labels_on(hints, .Mine), []string{"Take back"}), "the run's Take back")
	testing.expect(t, slice.equal(hint_labels_on(hints, .Tools), []string{"Tools"}), "the run's Tools")
	seated := hud
	seated.field_view.seat = .Seated
	no_pipette(t, screen_context, seated, "seated")
	tech_demo := screen_context
	tech_demo.content.field.tech_demo = true
	no_pipette(t, tech_demo, hud, "the tech demo")
	falling := screen_context
	falling.arrival_falling = true
	no_pipette(t, falling, hud, "the fall")

	// An aimed cable, nothing behind it.
	light := test_item(items, "light_cable")
	append(&world.entities.cables.cables, Cable{item = light})
	cable := hud
	cable.aimed_cable = 0
	cable.field_view.frame_target = {}
	testing.expect_value(t, hud_pipette_item(screen_context, cable), light)

	// The block world: the raycast's entity.
	player.target = Raycast_Hit{hit = true, block = {4, 1, 4}, entity = chest}
	hints, _ = world_glyph_hints(screen_context, Hud_Context{field_view_set = true})
	testing.expectf(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Inventory, .Tools, .Pause}), "the block world: Open, Pipette, Pause, not %v", hint_buttons(hints))
	testing.expect_value(t, hints[0].label, "Open")
	testing.expect_value(t, hints[1].label, "Pipette")
}

// Work item 0216, the fix round: what the held item does outranks the
// pipette's hint. At every audited size, text scale and glyph set, walking
// or not, a bar with a pipette target draws what the bar drew before 0216
// (world_glyph_hints with pipette false), the Tools hint as Pipette where
// "Pipette" displaces nothing and as Tools where it would; with nothing
// held the same hints, with or without Pipette. Pipette shows at the
// default size with every held case.
@(test)
test_the_pipette_hint_gives_way_at_every_size :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	theme, theme_problem := parse_ui_theme(#load("../data/ui/theme.sjson"), "data/ui/theme.sjson")
	testing.expect_value(t, theme_problem, "")
	world: World
	defer destroy_world(&world)
	machines := make_test_machines()
	items := make_test_items()
	entities := &world.entities
	chest := add_entity(entities, machines, test_machine(machines, "wooden_chest"), {4, 1, 4}, 0)
	broken := add_entity(entities, machines, test_machine(machines, "steel_furnace"), {8, 1, 4}, 0)
	entity_common(entities, broken).broken = true
	switch_handle := add_entity(entities, machines, test_machine(machines, "power_switch"), {12, 1, 4}, 0)
	foundation := add_entity(entities, machines, test_foundation(machines), {16, 1, 4}, 0)
	append(&entities.cables.cables, Cable{item = test_item(items, "light_cable")})
	player := Player{target = {entity = NO_ENTITY}, inventory = make_inventory(HOTBAR_SLOT_COUNT, context.temp_allocator)}
	screen_context := Screen_Context{world = &world, player = &player, items = items, machines = machines}
	Case :: struct {
		name:  string,
		aimed: Entity_Handle,
		cable: int,
		held:  string,
		tool:  Field_Held_Tool,
		field: bool,
	}
	cases := []Case {
		{"a chest, a furnace held", chest, -1, "stone_furnace", .Machine, true},
		{"a broken furnace, a furnace held", broken, -1, "stone_furnace", .Machine, true},
		{"a switch behind a cable, a cable held", switch_handle, 0, "light_cable", .Cable, true},
		{"a foundation, a furnace held", foundation, -1, "stone_furnace", .Machine, true},
		{"a chest, nothing held", chest, -1, "", .Hand, true},
		{"a foundation, nothing held", foundation, -1, "", .Hand, true},
		{"a chest in the block world", chest, -1, "", .Hand, false},
	}
	pipette, tools := text("hint_pipette"), text("hint_tools")
	bindings := shipped_default_bindings(t)
	settings := DEFAULT_SETTINGS
	sizes := UI_AUDIT_SIZES
	for entry in cases {
		hold_test_stack(&player, entry.held == "" ? EMPTY_STACK : Item_Stack{test_item(items, entry.held), 1})
		hud := Hud_Context{field_view_set = true, field_session = entry.field, aimed_cable = entry.cable}
		hud.field_view.tool = entry.tool
		player.target = Raycast_Hit{entity = NO_ENTITY}
		if entry.field {
			hud.field_view.frame_target = Frame_Raycast_Hit{hit = true, occupant = {handle = entity_occupant_handle(entry.aimed)}}
		} else {
			player.target = Raycast_Hit{hit = true, entity = entry.aimed}
		}
		testing.expectf(t, hud_pipette_item(screen_context, hud) != NO_ITEM, "%s: a tap picks something", entry.name)
		for walking in ([2]bool{false, true}) {
			player.on_ground = true
			player.velocity = walking ? {1, 0, 0} : {}
			for size in sizes {
				for text_scale in UI_AUDIT_TEXT_SCALES {
					settings.text_scale = text_scale
					for device in Input_Device {
						state := Ui_State{theme = theme, active_device = device, bindings = bindings}
						defer destroy_ui_state(&state)
						ui_begin(&state, {}, size.pixels, 1.0 / 60, size.scale, 1, ui_accessibility(settings))
						state.active_device = device
						shares := glyph(&state, .Interact) == glyph(&state, .Inventory)
						hints, kept := world_glyph_hints(screen_context, hud, shares)
						before, before_kept := world_glyph_hints(screen_context, hud, shares, false)
						testing.expectf(t, len(hints) == len(before) + (entry.held == "" ? 1 : 0), "%s: one Pipette hint", entry.name)
						drawn := glyph_bar_layout_hints(hud_world_glyph_bar_layout(&state, hints, kept, before, before_kept, 1))
						expected := glyph_bar_layout_hints(hud_glyph_bar_layout(&state, before, before_kept, false, 1))
						case_text := fmt.tprintf("%s, walking %v, %v scale %.1f text %.1f %v", entry.name, walking, size.pixels, size.scale, text_scale, device)
						// The drawn hints read without Pipette, or with it as Tools.
						read := make([dynamic]Glyph_Hint, context.temp_allocator)
						shown := false
						for hint in drawn {
							if hint.label != pipette {
								append(&read, hint)
								continue
							}
							shown = true
							if entry.held != "" {
								append(&read, Glyph_Hint{.Tools, tools})
							}
						}
						testing.expectf(t, slice.equal(read[:], expected), "%s: %v, before %v", case_text, drawn, expected)
						if entry.aimed == chest && entry.held != "" && size == sizes[0] && text_scale == 1 {
							testing.expectf(t, shown, "%s: Pipette shows", case_text)
						}
					}
				}
			}
		}
	}
}

// Work item 0223: the chair's Interact hint is Unbuckle strapped in,
// Stand seated and Sit standing aimed at the chair, none otherwise, none
// while the world falls; strapped in, the bar shows no held hints and,
// with Interact on the Inventory's control, neither Open nor Inventory.
@(test)
test_the_chair_hints_unbuckle_stand_and_sit :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	world: World
	defer destroy_world(&world)
	machines := make_test_machines()
	items := make_test_items()
	place_test_pod(&world.entities, machines)
	pod, frame, _ := find_pod(&world.entities, machines)
	machine := machines.machines[pod.machine]
	corner := rotate_footprint_cell({machine.seat.cells.from.x, machine.seat.cells.from.z}, machine.footprint.x, machine.footprint.z, pod.rotation)
	chair := Frame_Raycast_Hit{hit = true, frame = frame.id, cell = pod.origin + {corner.x, 1, corner.y}, occupant = {handle = entity_occupant_handle(pod.handle)}}
	player := Player{target = {entity = NO_ENTITY}, inventory = make_inventory(HOTBAR_SLOT_COUNT, context.temp_allocator)}
	hold_test_stack(&player, Item_Stack{test_item(items, "stone_furnace"), 1})
	screen_context := Screen_Context{world = &world, player = &player, items = items, machines = machines}
	hud := Hud_Context{field_view_set = true, field_session = true}
	hud.field_view.tool = .Machine
	testing.expect_value(t, field_pod_seat_hint_key(screen_context, hud), "")
	hud.field_view.frame_target = chair
	testing.expect_value(t, field_pod_seat_hint_key(screen_context, hud), "hint_sit")
	hud.field_view.frame_target = {}
	hud.field_view.seat = .Seated
	testing.expect_value(t, field_pod_seat_hint_key(screen_context, hud), "hint_stand")
	hud.field_view.seat = .Strapped
	testing.expect_value(t, field_pod_seat_hint_key(screen_context, hud), "hint_unbuckle")
	hints, kept := world_glyph_hints(screen_context, hud, true)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Interact, .Pause}), "Unbuckle, Pause")
	testing.expect_value(t, hints[0].label, "Unbuckle")
	testing.expect_value(t, kept, 1)
	falling := screen_context
	falling.arrival_falling = true
	testing.expect_value(t, field_pod_seat_hint_key(falling, hud), "")
	hints, _ = world_glyph_hints(falling, hud)
	testing.expect(t, !slice.contains(hint_buttons(hints), Glyph_Button.Interact), "no Interact while falling")
	testing.expect(t, !slice.contains(hint_buttons(hints), Glyph_Button.Use_Item), "no held hints strapped in")
	hud.field_session = false
	testing.expect_value(t, field_pod_seat_hint_key(screen_context, hud), "")
}

// Work item 0358: aimed at a cradle cell the bar says Wait, cradled Stop
// waiting, kept as the first hint; nothing while the world falls. The
// wait's line is the lone unit's, or counts the waiting units.
@(test)
test_the_cradle_hints_wait_and_stop_waiting :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	world: World
	defer destroy_world(&world)
	machines := make_test_machines()
	place_test_pod(&world.entities, machines)
	pod, frame, _ := find_pod(&world.entities, machines)
	machine := machines.machines[pod.machine]
	corner := rotate_footprint_cell({machine.cradle.cells.from.x, machine.cradle.cells.from.z}, machine.footprint.x, machine.footprint.z, pod.rotation)
	cradle := Frame_Raycast_Hit{hit = true, frame = frame.id, cell = pod.origin + {corner.x, machine.cradle.cells.from.y, corner.y}, occupant = {handle = entity_occupant_handle(pod.handle)}}
	player := Player{target = {entity = NO_ENTITY}, inventory = make_inventory(HOTBAR_SLOT_COUNT, context.temp_allocator)}
	screen_context := Screen_Context{world = &world, player = &player, items = make_test_items(), machines = machines}
	hud := Hud_Context{field_view_set = true, field_session = true}
	hud.field_view.frame_target = cradle
	testing.expect_value(t, field_pod_seat_hint_key(screen_context, hud), "hint_wait")
	hud.field_view.frame_target = {}
	hud.field_view.seat = .Cradled
	testing.expect_value(t, field_pod_seat_hint_key(screen_context, hud), "hint_stop_waiting")
	hints, kept := world_glyph_hints(screen_context, hud, true)
	testing.expect_value(t, hints[0].button, Glyph_Button.Interact)
	testing.expect_value(t, hints[0].label, "Stop waiting")
	testing.expect_value(t, kept, 1)
	falling := screen_context
	falling.arrival_falling = true
	testing.expect_value(t, field_pod_seat_hint_key(falling, hud), "")
	testing.expect_value(t, hud_waiting_text(1, 1), "Waiting in the cradle")
	testing.expect_value(t, hud_waiting_text(1, 3), "Waiting in the cradle: 1 of 3 units")
}

// Work item 0296: the jet bar shows while the budget is below full and
// the CHEAT tag while cheat movement is on; neither draws otherwise.
@(test)
test_the_jet_bar_and_cheat_tag_follow_the_field_player :: proc(t: ^testing.T) {
	tuning := Field_Player_Tuning{jet_budget_ticks = 90}
	full := Field_Player{jet_budget_ticks = 90}
	half := Field_Player{jet_budget_ticks = 45}
	_, shown := jet_bar_fraction(full, tuning)
	testing.expect(t, !shown, "a full budget shows no bar")
	fraction, half_shown := jet_bar_fraction(half, tuning)
	testing.expect(t, half_shown)
	testing.expect_value(t, fraction, 0.5)
	_, no_budget := jet_bar_fraction(half, {})
	testing.expect(t, !no_budget, "a tuning without a budget shows no bar")
	use_shipped_strings()
	defer thread_string_table = nil
	state: Ui_State
	defer destroy_ui_state(&state)
	ui_begin(&state, {}, {1920, 1080}, 0.5, 1, 1)
	draw_cheat_tag(&state, full)
	testing.expect_value(t, len(state.draw_list), 0)
	draw_cheat_tag(&state, Field_Player{cheat_movement = true})
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("hud_cheat_movement")))
	testing.expect_value(t, text("hud_cheat_movement"), "CHEAT")
	clear(&state.draw_list)
	draw_jet_bar(&state, full, tuning)
	testing.expect_value(t, len(state.draw_list), 0)
	draw_jet_bar(&state, half, tuning)
	testing.expect(t, len(state.draw_list) > 0, "a half budget draws the bar")
}

// Work item 0297: Torch on shows after Sprint and before Pause while the
// torchlight is on, outside the kept hints.
@(test)
test_the_torchlight_hint_shows_while_it_is_on :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	world: World
	defer destroy_world(&world)
	player := Player{target = {entity = NO_ENTITY}, inventory = make_inventory(HOTBAR_SLOT_COUNT, context.temp_allocator)}
	player.on_ground, player.velocity.x = true, 1
	screen_context := Screen_Context{world = &world, player = &player}
	hud := Hud_Context{field_view_set = true}
	testing.expect(t, sprint_hint_shown(player))
	hints, kept := world_glyph_hints(screen_context, hud)
	testing.expect(t, !slice.contains(hint_buttons(hints), Glyph_Button.Torchlight))
	hud.torchlight = true
	lit, lit_kept := world_glyph_hints(screen_context, hud)
	testing.expect(t, slice.equal(hint_buttons(lit), []Glyph_Button{.Sprint, .Torchlight, .Inventory, .Pause}), "Sprint, Torch on, Inventory, Pause")
	testing.expect_value(t, lit[1].label, "Torch on")
	testing.expect_value(t, lit_kept, kept)
}

// Work item 0295: a bucket's tool line counts the litres it poured or
// drained at the field's spacing; 0 spacing reads 0 L.
@(test)
test_the_bucket_tool_line_counts_the_litres :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	player := Field_Player{tool = .Water, poured_fill = 254, drained_fill = 127}
	line, shown := field_tool_line(player, {}, .None, 1000)
	testing.expect(t, shown)
	testing.expect_value(t, line, "Water bucket, 1000 L poured")
	player.tool = .Drain
	line, _ = field_tool_line(player, {}, .None, 1000)
	testing.expect_value(t, line, "Drain bucket, 500 L drained")
	line, _ = field_tool_line(player, {}, .None, 0)
	testing.expect_value(t, line, "Drain bucket, 0 L drained")
}

// Work item 0295: the crosshair's lines are fitted to the screen's width;
// a water pump's longest line at 960 by 540 with the largest text stays
// inside it.
@(test)
test_the_pump_line_fits_the_quarter_screen_at_the_largest_text :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	pump := Fluid_Machine{state = .Output_Full, water_pump = {mode = .Source, sample_millilitres = 1_000_000, moved_fill = 274_320}}
	line := water_pump_status_text(pump, "Water pump")
	testing.expect_value(t, line, "Water pump  Source  Output full  1080000 L moved")
	state: Ui_State
	defer destroy_ui_state(&state)
	accessibility := DEFAULT_UI_ACCESSIBILITY
	accessibility.text_scale = 1.6
	ui_begin(&state, {}, {960, 540}, 1.0 / 60, 1, 1, accessibility)
	testing.expect_value(t, draw_target_status(&state, line, 0), 1)
	drawn := 0
	for command in state.draw_list {
		if command.kind != .Text {
			continue
		}
		drawn += 1
		testing.expect(t, command.rectangle.x >= 0 && command.rectangle.x + command.rectangle.width <= state.screen_units.x, "the line's area is on the screen")
		testing.expectf(t, ui_text_width(&state, command.text, UI_BODY_TEXT_SIZE) <= command.rectangle.width, "%q fits %v", command.text, command.rectangle.width)
	}
	testing.expect_value(t, drawn, 1)
}

// The commands of a draw list whose rectangle's centre lies in the area.
draw_commands_in :: proc(commands: []Draw_Command, area: Ui_Rectangle) -> [dynamic]Draw_Command {
	found := make([dynamic]Draw_Command, context.temp_allocator)
	for command in commands {
		centre := [2]f32{command.rectangle.x + command.rectangle.width / 2, command.rectangle.y + command.rectangle.height / 2}
		if rectangle_contains(area, centre) {
			append(&found, command)
		}
	}
	return found
}

draw_commands_have_fill :: proc(commands: []Draw_Command, color: Ui_Color) -> bool {
	for command in commands {
		if command.kind == .Fill && command.color == color {
			return true
		}
	}
	return false
}

// Work item 0278: a toolbar slot counts its kind over every stack, an
// absent kind shows its icon under the shade with its name dim, and a
// slot that names nothing draws no icon.
@(test)
test_the_toolbar_shows_counts_and_greys_an_absent_kind :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	state: Ui_State
	defer destroy_ui_state(&state)
	items := make_test_items()
	dirt, furnace := test_item(items, "dirt"), test_item(items, "stone_furnace")
	player := make_player({}, context.temp_allocator)
	player.inventory.slots[2] = Item_Stack{dirt, 200}
	player.inventory.slots[30] = Item_Stack{dirt, 50}
	player.toolbars[0][0] = dirt
	player.toolbars[0][1] = furnace
	player.selected_hotbar_slot = 1
	test_ui_frame(&state, {})
	draw_hud_toolbars(&state, player, items, 1)
	rectangles := hud_toolbar_row_rectangles(ui_safe_area(&state), 1, 0)
	present := draw_commands_in(state.draw_list[:], rectangles[0])
	testing.expect(t, draw_list_has_text(present[:], "250"))
	testing.expect(t, !draw_commands_have_fill(present[:], HUD_EMPTY_KIND_SHADE), "a present kind is not shaded")
	absent := draw_commands_in(state.draw_list[:], rectangles[1])
	testing.expect(t, draw_commands_have_fill(absent[:], HUD_EMPTY_KIND_SHADE), "an absent kind is shaded")
	testing.expect(t, !draw_list_has_text(absent[:], "0"), "an absent kind draws no count")
	for command in draw_commands_in(state.draw_list[:], rectangles[2]) {
		testing.expectf(t, command.kind == .Fill || command.kind == .Outline, "a slot that names nothing draws %v", command.kind)
	}
	name := item_name(items, furnace)
	name_found := false
	for command in state.draw_list {
		if command.kind == .Text && command.text == name {
			name_found = true
			testing.expect_value(t, command.color, UI_DIM_TEXT_COLOR)
		}
	}
	testing.expect(t, name_found, "the absent kind is named")
}

// Work item 0278: two toolbars with the second active: row 0 draws the
// second's kinds with the selected outline, row 1 above it the first's
// under the inactive shade, the name above row 1 and the glyph bar's
// bottom above that, at 1080p.
@(test)
test_two_toolbars_stack_with_the_active_one_lowest :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	state: Ui_State
	defer destroy_ui_state(&state)
	items := make_test_items()
	dirt, stone := test_item(items, "dirt"), test_item(items, "stone")
	player := make_player({}, context.temp_allocator)
	player.inventory.slots[0] = Item_Stack{dirt, 3}
	player.inventory.slots[1] = Item_Stack{stone, 4}
	player.toolbars[0][0] = dirt
	player.toolbars[1][0] = stone
	player.active_toolbar = 1
	test_ui_frame(&state, {})
	draw_hud_toolbars(&state, player, items, 2)
	safe := ui_safe_area(&state)
	row_0 := hud_toolbar_row_rectangles(safe, 0, 0)
	row_1 := hud_toolbar_row_rectangles(safe, 0, 1)
	testing.expect(t, draw_list_has_text(draw_commands_in(state.draw_list[:], row_0[0])[:], "4"), "row 0 holds the active toolbar's stone")
	testing.expect(t, draw_list_has_text(draw_commands_in(state.draw_list[:], row_1[0])[:], "3"), "row 1 holds the first toolbar's dirt")
	shaded := 0
	for rectangle in row_1 {
		for command in draw_commands_in(state.draw_list[:], rectangle) {
			if command.kind == .Fill && command.color == HUD_INACTIVE_ROW_SHADE && command.rectangle == rectangle {
				shaded += 1
			}
		}
	}
	testing.expect_value(t, shaded, HOTBAR_SLOT_COUNT)
	testing.expect(t, !draw_commands_have_fill(draw_commands_in(state.draw_list[:], row_0[3])[:], HUD_INACTIVE_ROW_SHADE), "row 0 is not shaded")
	testing.expect_value(t, row_1[0].y, f32(838))
	for command in state.draw_list {
		if command.kind == .Text && command.text == item_name(items, stone) {
			testing.expect_value(t, command.rectangle.y, f32(774))
			testing.expect_value(t, command.color, UI_TEXT_COLOR)
		}
	}
	testing.expect_value(t, hud_glyph_bar_above_bottom(safe, 2), f32(766))
	testing.expect_value(t, hud_glyph_bar_above_bottom(safe, 1), f32(854))
}
