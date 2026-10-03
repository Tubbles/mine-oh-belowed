package game

import "core:strings"
import "core:testing"
import rl "shared:raylib"

make_test_machines :: proc() -> Machine_Registry {
	file, error := parse_machines_file(#load("../data/machines.sjson"), context.temp_allocator)
	assert(error == nil)
	registry, problem := resolve_machine_registry(file, make_test_items(), make_test_fluids(), context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

make_test_fluids :: proc() -> Fluid_Registry {
	file, error := parse_fluids_file(#load("../data/fluids.sjson"), context.temp_allocator)
	assert(error == nil)
	registry, problem := resolve_fluid_registry(file, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

make_test_content :: proc() -> Simulation_Content {
	items := make_test_items()
	recipes, technologies := make_test_recipes(items)
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	veins, problem := resolve_vein_content(generator.veins, items, context.temp_allocator)
	assert(problem == "", problem)
	machines := make_test_machines()
	machines.lab_packs = technologies.science_packs
	crafting_problem := validate_crafting_machine_recipes(machines, recipes)
	assert(crafting_problem == "", crafting_problem)
	return Simulation_Content {
		blocks = make_test_registry(),
		items = items,
		machines = machines,
		fluids = make_test_fluids(),
		recipes = recipes,
		technologies = technologies,
		veins = veins,
		contracts = make_test_contracts(items),
	}
}

test_machine :: proc(machines: Machine_Registry, id: string) -> Machine_Id {
	for machine, index in machines.machines {
		if machine.id == id {
			return Machine_Id(index)
		}
	}
	panic(id)
}

@(test)
test_machine_data_loads :: proc(t: ^testing.T) {
	items := make_test_items()
	machines := make_test_machines()
	testing.expect_value(t, len(machines.machines), 62)
	wooden := machines.machines[test_machine(machines, "wooden_chest")]
	testing.expect_value(t, wooden.kind, Machine_Kind.Chest)
	testing.expect_value(t, wooden.slot_count, 16)
	testing.expect_value(t, wooden.footprint, [3]i32{1, 1, 1})
	testing.expect_value(t, machines.machines[test_machine(machines, "iron_chest")].slot_count, 32)
	furnace := machines.machines[test_machine(machines, "stone_furnace")]
	testing.expect_value(t, furnace.kind, Machine_Kind.Furnace)
	testing.expect_value(t, furnace.footprint, [3]i32{2, 2, 2})
	testing.expect_value(t, furnace.speed_percent, 100)
	testing.expect_value(t, furnace.fuel_power_watts, 90_000)
	testing.expect_value(t, furnace.item, test_item(items, "stone_furnace"))
	testing.expect_value(t, item_places_machine(machines, test_item(items, "stone_furnace")), test_machine(machines, "stone_furnace"))
	testing.expect_value(t, item_places_machine(machines, test_item(items, "stone")), NO_MACHINE)
	testing.expect_value(t, item_places_machine(machines, NO_ITEM), NO_MACHINE)
	burner := machines.machines[test_machine(machines, "burner_inserter")]
	testing.expect_value(t, burner.kind, Machine_Kind.Inserter)
	testing.expect_value(t, burner.slot_count, 1)
	testing.expect_value(t, burner.items_per_minute, 36)
	testing.expect_value(t, burner.fuel_power_watts, 94_000)
	electric := machines.machines[test_machine(machines, "inserter")]
	testing.expect_value(t, electric.slot_count, 0)
	testing.expect_value(t, electric.electric_power_watts, 13_000)
	testing.expect_value(t, electric.filter_slot_count, 0)
	testing.expect_value(t, machines.machines[test_machine(machines, "filter_inserter")].filter_slot_count, 1)
	drill := machines.machines[test_machine(machines, "burner_mining_drill")]
	testing.expect_value(t, drill.kind, Machine_Kind.Drill)
	testing.expect_value(t, drill.footprint, [3]i32{2, 2, 2})
	testing.expect_value(t, drill.slot_count, 1)
	testing.expect_value(t, drill.items_per_minute, 15)
	testing.expect_value(t, drill.rate_reference_ore_percent, 80)
	testing.expect_value(t, drill.fuel_power_watts, 150_000)
	testing.expect_value(t, drill.item, test_item(items, "burner_mining_drill"))
	splitter := machines.machines[test_machine(machines, "splitter")]
	testing.expect_value(t, splitter.kind, Machine_Kind.Splitter)
	testing.expect_value(t, splitter.footprint, [3]i32{1, 1, 2})
	testing.expect_value(t, splitter.belt_speed_units_per_second, 480)
	testing.expect_value(t, splitter.item, test_item(items, "splitter"))
}

@(test)
test_machine_strings_exist :: proc(t: ^testing.T) {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	testing.expect(t, error == nil)
	for machine in make_test_machines().machines {
		testing.expectf(t, machine.name_key in table.entries, "missing string %q", machine.name_key)
	}
	for key in furnace_state_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in inserter_state_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in drill_state_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for vein_type in make_test_content().veins.types {
		testing.expectf(t, vein_type.name_key in table.entries, "missing string %q", vein_type.name_key)
	}
	for key in ([?]string{"inserter_filter", "hint_set_filter", "hint_clear_filter", "drill_remaining", "drill_infinite", "drill_rate"}) {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in ([?]string{"splitter_input_priority", "splitter_output_priority", "splitter_filter_side"}) {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in splitter_priority_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in splitter_side_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for key in fluid_machine_state_keys {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
	for fluid in make_test_fluids().fluids {
		testing.expectf(t, fluid.name_key in table.entries, "missing string %q", fluid.name_key)
	}
	for key in ([?]string{"fluid_none", "fluid_of", "fluid_flow_in", "fluid_flow_out", "fluid_mixing_refused"}) {
		testing.expectf(t, key in table.entries, "missing string %q", key)
	}
}

resolve_test_machines :: proc(definitions: []Machine_Definition) -> string {
	registry, problem := resolve_machine_registry(Machines_File{machines = definitions}, make_test_items(), make_test_fluids(), context.temp_allocator)
	if problem == "" {
		destroy_machine_registry(registry, context.temp_allocator)
	}
	return problem
}

@(test)
test_machine_data_rejects_bad_definitions :: proc(t: ^testing.T) {
	chest := Machine_Definition {
		id = "chest",
		name_key = "machine_wooden_chest",
		item = "wooden_chest",
		kind = "chest",
		footprint = {1, 1, 1},
		slots = 16,
	}
	testing.expect_value(t, resolve_test_machines({chest}), "")
	unknown_item := chest
	unknown_item.item = "no_such_item"
	testing.expect(t, resolve_test_machines({unknown_item}) != "")
	block_item := chest
	block_item.item = "stone"
	testing.expect(t, resolve_test_machines({block_item}) != "")
	second := chest
	second.id = "second"
	testing.expect(t, resolve_test_machines({chest, second}) != "")
	no_slots := chest
	no_slots.slots = 0
	testing.expect(t, resolve_test_machines({no_slots}) != "")
	flat := chest
	flat.footprint.height = 0
	testing.expect(t, resolve_test_machines({flat}) != "")
	unknown_kind := chest
	unknown_kind.kind = "assembler"
	testing.expect(t, resolve_test_machines({unknown_kind}) != "")
	furnace := Machine_Definition {
		id = "furnace",
		name_key = "machine_stone_furnace",
		item = "stone_furnace",
		kind = "furnace",
		footprint = {2, 2, 2},
		fuel_slots = 1,
		input_slots = 1,
		output_slots = 2,
		speed = 1,
		fuel_power_kilowatts = 90,
	}
	testing.expect_value(t, resolve_test_machines({furnace}), "")
	no_byproduct_slot := furnace
	no_byproduct_slot.output_slots = 1
	testing.expect(t, resolve_test_machines({no_byproduct_slot}) != "")
	unpowered := furnace
	unpowered.fuel_power_kilowatts = 0
	testing.expect(t, resolve_test_machines({unpowered}) != "")
	two_inputs := furnace
	two_inputs.input_slots = 2
	testing.expect(t, resolve_test_machines({two_inputs}) != "")
	inserter := Machine_Definition {
		id = "inserter",
		name_key = "machine_burner_inserter",
		item = "burner_inserter",
		kind = "inserter",
		footprint = {1, 1, 1},
		items_per_minute = 36,
		fuel_slots = 1,
		fuel_power_kilowatts = 94,
		reach_millimetres = 2000,
	}
	testing.expect_value(t, resolve_test_machines({inserter}), "")
	no_reach := inserter
	no_reach.reach_millimetres = 0
	testing.expect(t, resolve_test_machines({no_reach}) != "")
	far := inserter
	far.reach_millimetres = MAXIMUM_ARM_REACH_MILLIMETRES + 1
	testing.expect(t, resolve_test_machines({far}) != "")
	no_rate := inserter
	no_rate.items_per_minute = 0
	testing.expect(t, resolve_test_machines({no_rate}) != "")
	no_power := inserter
	no_power.fuel_slots = 0
	testing.expect(t, resolve_test_machines({no_power}) != "")
	wide := inserter
	wide.footprint.width = 2
	testing.expect(t, resolve_test_machines({wide}) != "")
	two_filters := inserter
	two_filters.filter_slots = 2
	testing.expect(t, resolve_test_machines({two_filters}) != "")
}

// open_cells (0186): boxes inside the footprint with from no greater than
// to, at most MAXIMUM_OPEN_CELL_BOXES; the pod's file record parses to
// its boxes.
@(test)
test_machine_open_cells_are_boxes_inside_the_footprint :: proc(t: ^testing.T) {
	room := Machine_Definition {
		id = "room",
		name_key = "machine_pod",
		kind = "pod",
		footprint = {width = 3, depth = 4, height = 2},
		open_cells = {{from = Machine_Cell_Definition{1, 0, 1}, to = Machine_Cell_Definition{2, 1, 3}}},
	}
	testing.expect_value(t, resolve_test_machines({room}), "")
	reversed := room
	reversed.open_cells = {{from = Machine_Cell_Definition{2, 0, 1}, to = Machine_Cell_Definition{1, 1, 3}}}
	testing.expect(t, resolve_test_machines({reversed}) != "")
	outside := room
	outside.open_cells = {{from = Machine_Cell_Definition{0, 0, 0}, to = Machine_Cell_Definition{2, 2, 3}}}
	testing.expect(t, resolve_test_machines({outside}) != "")
	negative := room
	negative.open_cells = {{from = Machine_Cell_Definition{-1, 0, 0}, to = Machine_Cell_Definition{0, 0, 0}}}
	testing.expect(t, resolve_test_machines({negative}) != "")
	no_to := room
	no_to.open_cells = {{from = Machine_Cell_Definition{1, 0, 1}}}
	testing.expect(t, resolve_test_machines({no_to}) != "")
	no_from := room
	no_from.open_cells = {{to = Machine_Cell_Definition{2, 1, 3}}}
	testing.expect(t, resolve_test_machines({no_from}) != "")
	too_many := room
	too_many.open_cells = make([]Machine_Cell_Box_Definition, MAXIMUM_OPEN_CELL_BOXES + 1, context.temp_allocator)
	testing.expect(t, resolve_test_machines({too_many}) != "")

	machines := make_test_machines()
	pod := machines.machines[find_machine_of_kind(machines, .Pod)]
	testing.expect_value(t, pod.open_cell_box_count, 4)
	testing.expect_value(t, pod.open_cells[3], Cell_Box{from = {9, 0, 1}, to = {10, 5, 6}})
}

// Work item 0198: a footprint side may be 12 cells (the pod's length),
// not 13.
@(test)
test_a_footprint_side_of_twelve_is_accepted :: proc(t: ^testing.T) {
	chest := Machine_Definition {
		id = "chest",
		name_key = "machine_wooden_chest",
		item = "wooden_chest",
		kind = "chest",
		footprint = {width = 12, depth = 1, height = 1},
		slots = 16,
	}
	testing.expect_value(t, resolve_test_machines({chest}), "")
	chest.footprint.width = 13
	testing.expect_value(t, resolve_test_machines({chest}), `machine "chest" has a footprint side outside 1 to 12`)
}

// A test pod of 6 by 4 by 3 cells with a cabin from (1, 0, 1) to (4, 1,
// 2), and a locker of 1 by 2 by 2 cells to list as its fixture.
test_fixture_definitions :: proc(fixtures: []Pod_Fixture_Definition) -> []Machine_Definition {
	cabin := make([]Machine_Cell_Box_Definition, 1, context.temp_allocator)
	cabin[0] = {from = Machine_Cell_Definition{1, 0, 1}, to = Machine_Cell_Definition{4, 1, 2}}
	pod := Machine_Definition {
		id = "room",
		name_key = "machine_pod",
		kind = "pod",
		footprint = {width = 6, depth = 4, height = 3},
		open_cells = cabin,
		fixtures = fixtures,
	}
	locker := Machine_Definition {
		id = "locker",
		name_key = "machine_pod_locker",
		kind = "locker",
		footprint = {width = 1, depth = 2, height = 2},
		slots = 4,
	}
	chest := Machine_Definition {
		id = "chest",
		name_key = "machine_wooden_chest",
		item = "wooden_chest",
		kind = "chest",
		footprint = {1, 1, 1},
		slots = 16,
	}
	definitions := make([]Machine_Definition, 3, context.temp_allocator)
	definitions[0], definitions[1], definitions[2] = pod, locker, chest
	return definitions
}

// Work item 0198: validate_pod_fixtures refuses each wrong list, a valid
// one resolves to its machines and boxes, and the shipped pod lists its
// five.
@(test)
test_the_pod_fixtures_are_checked :: proc(t: ^testing.T) {
	refusals := []struct {
		fixtures: []Pod_Fixture_Definition,
		words:    string,
	} {
		{{{machine = "nothing", cell = {0, 0, 0}}}, "names unknown machine"},
		{{{machine = "chest", cell = {0, 0, 0}}}, "not a hatch, locker"},
		{{{machine = "locker", cell = {0, 0, 0}, rotation = 4}}, "outside 0 to 3"},
		{{{machine = "locker", cell = {5, 0, 3}}}, "is not inside the footprint"},
		{{{machine = "locker", cell = {0, 0, 0}}, {machine = "locker", cell = {0, 0, 1}}}, "fixtures 0 and 1 overlap"},
		{{{machine = "locker", cell = {2, 0, 1}, rotation = 1}}, "stands on the cabin's spawn"},
	}
	for refusal in refusals {
		problem := resolve_test_machines(test_fixture_definitions(refusal.fixtures))
		testing.expectf(t, strings.contains(problem, refusal.words), "%q lacks %q", problem, refusal.words)
	}
	nine := make([]Pod_Fixture_Definition, MAXIMUM_POD_FIXTURES + 1, context.temp_allocator)
	testing.expect(t, strings.contains(resolve_test_machines(test_fixture_definitions(nine)), "more than 8 fixtures"))
	not_a_pod := test_fixture_definitions({{machine = "locker", cell = {0, 0, 0}}})
	not_a_pod[2].fixtures = not_a_pod[0].fixtures
	testing.expect(t, strings.contains(resolve_test_machines(not_a_pod), "which only a pod may"))

	valid := test_fixture_definitions({{machine = "locker", cell = {0, 0, 0}}, {machine = "locker", cell = {4, 0, 3}, rotation = 1}})
	registry, problem := resolve_machine_registry(Machines_File{machines = valid}, make_test_items(), make_test_fluids(), context.temp_allocator)
	testing.expect_value(t, problem, "")
	if problem == "" {
		room := registry.machines[0]
		testing.expect_value(t, room.fixture_count, 2)
		testing.expect_value(t, room.fixtures[1], Pod_Fixture{machine = 1, cell = {4, 0, 3}, rotation = 1})
		testing.expect_value(t, room.fixture_boxes[0], Cell_Box{from = {0, 0, 0}, to = {0, 1, 1}})
		testing.expect_value(t, room.fixture_boxes[1], Cell_Box{from = {4, 0, 3}, to = {5, 1, 3}})
	}

	machines := make_test_machines()
	pod := machines.machines[find_machine_of_kind(machines, .Pod)]
	testing.expect_value(t, pod.fixture_count, 5)
	testing.expect_value(t, pod.fixture_boxes[0], Cell_Box{from = {11, 0, 3}, to = {11, 3, 4}})
	testing.expect_value(t, pod.fixture_boxes[2], Cell_Box{from = {1, 0, 1}, to = {2, 3, 1}})
	testing.expect_value(t, machines.machines[pod.fixtures[0].machine].kind, Machine_Kind.Hatch)
}

// Work item 0198: the kinds placed in the pod refuse an item and the
// fields they do not use; a slide motion belongs to a hatch alone.
@(test)
test_the_world_placed_fixture_kinds_are_validated :: proc(t: ^testing.T) {
	hatch := Machine_Definition {
		id = "hatch",
		name_key = "machine_pod_hatch",
		kind = "hatch",
		model = "pod_hatch",
		footprint = {width = 1, depth = 2, height = 4},
		motion = {kind = "slide", axis = "y", amplitude = 3.95, period_seconds = 0.8},
	}
	testing.expect_value(t, validate_machine_definition({hatch}, 0), "")
	refused := make([dynamic]Machine_Definition, context.temp_allocator)
	with_item := hatch
	with_item.item = "wooden_chest"
	low := hatch
	low.footprint.height = 1
	with_open_cells := hatch
	with_open_cells.open_cells = {{from = Machine_Cell_Definition{0, 0, 0}, to = Machine_Cell_Definition{0, 0, 0}}}
	spinning := hatch
	spinning.motion = {kind = "spin", axis = "y", amplitude = 1, period_seconds = 1}
	still := hatch
	still.motion.amplitude = 0
	far := hatch
	far.motion.amplitude = 13
	append(&refused, with_item, low, with_open_cells, spinning, still, far)
	sliding_chest := Machine_Definition {
		id = "chest",
		name_key = "machine_wooden_chest",
		item = "wooden_chest",
		kind = "chest",
		model = "wooden_chest",
		footprint = {1, 1, 1},
		slots = 16,
		motion = hatch.motion,
	}
	locker := Machine_Definition {
		id = "locker",
		name_key = "machine_pod_locker",
		kind = "locker",
		footprint = {width = 1, depth = 2, height = 4},
		slots = 16,
	}
	testing.expect_value(t, validate_machine_definition({locker}, 0), "")
	empty_locker := locker
	empty_locker.slots = 0
	big_locker := locker
	big_locker.slots = MAXIMUM_CHEST_SLOTS + 1
	carried_locker := locker
	carried_locker.item = "wooden_chest"
	bench := Machine_Definition {
		id = "bench",
		name_key = "machine_crafting_bench",
		kind = "crafting_bench",
		footprint = {width = 1, depth = 2, height = 2},
		recipe_maker = "hand",
	}
	testing.expect_value(t, validate_machine_definition({bench}, 0), "")
	assembling_bench := bench
	assembling_bench.recipe_maker = "assembler"
	slotted_bench := bench
	slotted_bench.slots = 2
	carried_bench := bench
	carried_bench.item = "wooden_chest"
	generator := Machine_Definition {
		id = "generator",
		name_key = "machine_oxygen_generator",
		kind = "oxygen_generator",
		footprint = {width = 1, depth = 2, height = 3},
	}
	testing.expect_value(t, validate_machine_definition({generator}, 0), "")
	slotted_generator := generator
	slotted_generator.slots = 1
	carried_generator := generator
	carried_generator.item = "wooden_chest"
	append(&refused, sliding_chest, empty_locker, big_locker, carried_locker, assembling_bench, slotted_bench, carried_bench, slotted_generator, carried_generator)
	for definition in refused {
		testing.expectf(t, validate_machine_definition({definition}, 0) != "", "%s %v passes", definition.id, definition)
	}

	machines := make_test_machines()
	for id in ([4]string{"pod_hatch", "pod_locker", "crafting_bench", "oxygen_generator"}) {
		machine := machines.machines[test_machine(machines, id)]
		testing.expect(t, machine_kind_is_placed_by_world(machine_kind_names[machine.kind]), id)
		testing.expect_value(t, machine.item, NO_ITEM)
	}
}

// Work item 0199: a pod's first open_cells box is its cabin, on the
// floor row and 2 by 2 cells at least; the shipped record passes.
@(test)
test_a_pod_needs_a_cabin_on_its_floor :: proc(t: ^testing.T) {
	expected := `machine "room" is a pod whose first open_cells box is no cabin on its floor (y 0, 2 by 2 cells at least)`
	room := Machine_Definition {
		id = "room",
		name_key = "machine_pod",
		kind = "pod",
		footprint = {width = 3, depth = 4, height = 2},
	}
	testing.expect_value(t, resolve_test_machines({room}), expected)
	raised := room
	raised.open_cells = {{from = Machine_Cell_Definition{1, 1, 1}, to = Machine_Cell_Definition{2, 1, 3}}}
	testing.expect_value(t, resolve_test_machines({raised}), expected)
	narrow := room
	narrow.open_cells = {{from = Machine_Cell_Definition{1, 0, 1}, to = Machine_Cell_Definition{1, 1, 3}}}
	testing.expect_value(t, resolve_test_machines({narrow}), expected)
	shallow := room
	shallow.open_cells = {{from = Machine_Cell_Definition{1, 0, 1}, to = Machine_Cell_Definition{2, 1, 1}}}
	testing.expect_value(t, resolve_test_machines({shallow}), expected)
	machines := make_test_machines()
	testing.expect(t, find_machine_of_kind(machines, .Pod) != NO_MACHINE, "the shipped pod passes")
}

// Work item 0196: a foundation needs a colour of three channels from 0 to
// 255, not all zero, and the shipped tiers draw in theirs.
@(test)
test_a_foundation_needs_a_colour :: proc(t: ^testing.T) {
	definition := Machine_Definition{id = "test_foundation", kind = "foundation", footprint = {1, 1, 1}}
	testing.expect(t, validate_machine_kind_fields(definition, .Foundation) != "")
	definition.color = {256, 0, 0}
	testing.expect(t, validate_machine_kind_fields(definition, .Foundation) != "")
	definition.color = {150, 108, 66}
	testing.expect_value(t, validate_machine_kind_fields(definition, .Foundation), "")
	machines := make_test_machines()
	expected := [3]struct {
		id:    string,
		color: rl.Color,
	}{{"wooden_foundation", {150, 108, 66, 255}}, {"stone_brick_foundation", {150, 146, 138, 255}}, {"iron_foundation", {104, 112, 122, 255}}}
	for entry in expected {
		testing.expect_value(t, foundation_slab_color(machines.machines[test_machine(machines, entry.id)]), entry.color)
	}
}

// Work item 0197: a tree's record holds a model and no item, and is
// never an entity.
@(test)
test_a_tree_machine_has_no_item_and_no_entity :: proc(t: ^testing.T) {
	definition := Machine_Definition{id = "test_tree", kind = "tree", footprint = {6, 6, 9}, item = "log"}
	testing.expect_value(t, validate_machine_kind_fields(definition, .Tree), `tree "test_tree" cannot be placed by an item`)
	definition.item = ""
	testing.expect_value(t, validate_machine_kind_fields(definition, .Tree), "")
	machines := make_test_machines()
	pine := test_machine(machines, "pine_tree")
	testing.expect_value(t, machines.machines[pine].kind, Machine_Kind.Tree)
	testing.expect_value(t, machines.machines[pine].item, NO_ITEM)
	entities: Entities
	defer destroy_entities(&entities)
	testing.expect_value(t, add_entity(&entities, machines, pine, {}, 0), NO_ENTITY)
	testing.expect_value(t, entity_counts(&entities), [Entity_Kind]int{})
	testing.expect_value(t, len(entities.frames.occupants), 0)
}
