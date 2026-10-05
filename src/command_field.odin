package game

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

// The field world's forms of the commands (work item 0183,
// doc/commands.md, The field world): on a field session the commands read
// and move the field player (Player.field) in metres, latitude and
// longitude, a bearing from north and a pitch, place on a frame's cell,
// and list the sphere's veins, the frames and the entities on them. The
// commands that only mean something on the block world answer
// NO_BLOCK_WORLD_PROBLEM. Every write parses its numbers with integers
// (parse_decimal_word), never a float, since the line runs inside the
// tick on every machine of a lockstep session; floats appear only in the
// answers.

NO_BLOCK_WORLD_PROBLEM :: "no block world"
NO_FIELD_WORLD_PROBLEM :: "no field world"
DEFAULT_FIELD_VEIN_QUERY_RADIUS_METRES :: 128
DEFAULT_FIELD_ENTITY_QUERY_RADIUS_METRES :: 32
DEFAULT_FRAME_QUERY_RADIUS_METRES :: 64
// The integer digits of a decimal word.
MAXIMUM_DECIMAL_DIGITS :: 12

// Words.

// An optional minus, 1 to MAXIMUM_DECIMAL_DIGITS digits, optionally a dot
// and 1 to 3 digits, as thousandths. No exponent, no plus, no empty part.
parse_decimal_word :: proc(word: string) -> (thousandths: i64, ok: bool) {
	negative := strings.has_prefix(word, "-")
	rest := negative ? word[1:] : word
	whole, fraction := rest, ""
	if dot := strings.index_byte(rest, '.'); dot >= 0 {
		whole, fraction = rest[:dot], rest[dot + 1:]
		if len(fraction) == 0 || len(fraction) > 3 {
			return 0, false
		}
	}
	if len(whole) == 0 || len(whole) > MAXIMUM_DECIMAL_DIGITS {
		return 0, false
	}
	value: i64
	for character in transmute([]u8)whole {
		if character < '0' || character > '9' {
			return 0, false
		}
		value = value * 10 + i64(character - '0')
	}
	for character in transmute([]u8)fraction {
		if character < '0' || character > '9' {
			return 0, false
		}
		value = value * 10 + i64(character - '0')
	}
	for _ in len(fraction) ..< 3 {
		value *= 10
	}
	return negative ? -value : value, true
}

// Thousandths as a whole number when they are one, else with three
// decimals.
thousandths_text :: proc(thousandths: i64) -> string {
	if thousandths % 1000 == 0 {
		return fmt.tprintf("%d", thousandths / 1000)
	}
	return fmt.tprintf("%.3f", f64(thousandths) / 1000)
}

// A decimal word within minimum to maximum (thousandths), or the problem.
parse_ranged_decimal_word :: proc(word: string, minimum, maximum: i64, what: string) -> (thousandths: i64, problem: string) {
	parsed, ok := parse_decimal_word(word)
	if !ok || parsed < minimum || parsed > maximum {
		return 0, fmt.tprintf("%s must be a number from %s to %s with up to three decimals", what, thousandths_text(minimum), thousandths_text(maximum))
	}
	return parsed, ""
}

// Three words of metres, each within FAR_LIMIT_METRES of the centre.
parse_metres_words :: proc(words: []string, what: string) -> (position: World_Position, problem: string) {
	limit := i64(FAR_LIMIT_METRES) * 1000
	for word, axis in words[:3] {
		thousandths: i64
		if thousandths, problem = parse_ranged_decimal_word(word, -limit, limit, what); problem != "" {
			return {}, problem
		}
		position[axis] = thousandths * POSITION_UNITS_PER_METRE / 1000
	}
	return position, ""
}

// Rounded to the nearest unit, half away from zero.
millidegrees_to_angle_units :: proc(millidegrees: i64) -> i32 {
	scaled := abs(millidegrees) * ANGLE_UNITS_PER_TURN
	units := (scaled + 180_000) / 360_000
	return i32(millidegrees < 0 ? -units : units)
}

// Answers.

metres_text :: proc(position: World_Position) -> string {
	return fmt.tprintf("%.3f %.3f %.3f", f64(position.x) / POSITION_UNITS_PER_METRE, f64(position.y) / POSITION_UNITS_PER_METRE, f64(position.z) / POSITION_UNITS_PER_METRE)
}

// The midpoint of the centres of the footprint's corner cells.
entity_centre :: proc(frame: Frame, common: Entity_Common) -> World_Position {
	first := frame_cell_centre(frame, common.origin)
	last := frame_cell_centre(frame, common.origin + World_Coordinate(common.size) - {1, 1, 1})
	return first + (last - first) / 2
}

// The heading's bearing from the planet's north in degrees, turning the
// way the yaw turns (towards north cross up), rounded to the tenth the
// answers print and then wrapped into 0 up to 360, so a bearing a hair
// short of 360 reads 0.0.
field_player_bearing_degrees :: proc(player: Field_Player) -> f64 {
	heading := field_player_heading(player)
	north := frame_north_tangent(player.up)
	east := fixed_cross(north, player.up)
	degrees := math.to_degrees(math.atan2(f64(fixed_dot(heading, east)), f64(fixed_dot(heading, north))))
	tenths := math.round(degrees * 10)
	return math.mod(tenths + 3600, 3600) / 10
}

angle_units_to_degrees :: proc(angle: i32) -> f64 {
	return f64(angle) * 360 / ANGLE_UNITS_PER_TURN
}

// Metres between two world positions.
metres_between :: proc(first, second: World_Position) -> f64 {
	offset := [3]f64{f64(second.x - first.x), f64(second.y - first.y), f64(second.z - first.z)} / POSITION_UNITS_PER_METRE
	return math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
}

// Metres above the planet's sea level.
field_height_metres :: proc(planet: Planet, position: World_Position) -> f64 {
	_, _, distance := field_feet_coordinates(position)
	return distance - f64(planet.radius_metres + planet.sea_level_metres)
}

// "latitude <latitude> longitude <longitude> height <height>".
field_place_text :: proc(planet: Planet, position: World_Position) -> string {
	latitude, longitude, _ := field_feet_coordinates(position)
	return fmt.tprintf("latitude %.4f longitude %.4f height %.2f", latitude, longitude, field_height_metres(planet, position))
}

// Dispatch.

// The field forms of the commands; handled is false for a command (or a
// query subject) that serves both worlds alike.
field_world_command :: proc(command_context: Command_Context, name: string, arguments: []string) -> (response: Command_Response, handled: bool) {
	switch name {
	case "teleport":
		if len(arguments) == 1 && arguments[0] == "pad" {
			return command_error(NO_BLOCK_WORLD_PROBLEM), true
		}
		return command_field_teleport(command_context, arguments), true
	case "look":
		return command_look(command_context, arguments), true
	case "crouch":
		return command_crouch(command_context, arguments), true
	case "place":
		return command_field_place(command_context, arguments), true
	case "vein", "remove", "block", "insert", "recipe", "filter", "blueprint":
		return command_error(NO_BLOCK_WORLD_PROBLEM), true
	case "query":
		return field_query(command_context, arguments)
	}
	return {}, false
}

field_query :: proc(command_context: Command_Context, arguments: []string) -> (response: Command_Response, handled: bool) {
	subject := len(arguments) > 0 ? arguments[0] : ""
	rest := len(arguments) > 0 ? arguments[1:] : nil
	switch subject {
	case "player":
		return query_field_player(command_context), true
	case "world":
		return query_field_world(command_context), true
	case "veins":
		return query_field_veins(command_context, rest), true
	case "entities":
		return query_field_entities(command_context, rest), true
	case "frames":
		return query_frames(command_context, rest), true
	}
	return {}, false
}

// Writes.

// teleport <x> <y> <z> (metres), <latitude> <longitude> (the generated
// surface plus the spawn clearance) or pod (the cabin spawn). The feet are
// computed here, integer only, inside the tick on every machine.
command_field_teleport :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	usage :: "teleport <x> <y> <z> | teleport <latitude> <longitude> | teleport pod"
	simulation := command_context.simulation
	feet: World_Position
	problem: string
	switch {
	case len(arguments) == 1 && arguments[0] == "pod":
		spawn, found := field_pod_spawn(&simulation.world.entities, command_context.content.machines)
		if !found {
			return command_error("there is no pod")
		}
		feet = spawn.position
	case len(arguments) == 2:
		if feet, problem = surface_point_feet(simulation, arguments); problem != "" {
			return command_error("%s", problem)
		}
	case len(arguments) == 3:
		if feet, problem = parse_metres_words(arguments, "a position"); problem != "" {
			return command_error("%s", problem)
		}
	case:
		return usage_error(usage)
	}
	serve_command_request(command_context, Developer_Request{action = .Teleport_Field, field_position = feet})
	position := simulation.players[command_context.player].field.position
	return command_ok("at %s %s", metres_text(position), field_place_text(simulation.world.planet, position))
}

// The feet on the generated surface at a latitude and longitude word, the
// spawn clearance above it.
surface_point_feet :: proc(simulation: ^Simulation_State, words: []string) -> (feet: World_Position, problem: string) {
	latitude, longitude: i64
	if latitude, problem = parse_ranged_decimal_word(words[0], -90_000, 90_000, "the latitude"); problem != "" {
		return {}, problem
	}
	if longitude, problem = parse_ranged_decimal_word(words[1], -180_000, 180_000, "the longitude"); problem != "" {
		return {}, problem
	}
	generation := simulation.field.world.water_planet.generation
	direction := planet_direction_at(millidegrees_to_angle_units(latitude), millidegrees_to_angle_units(longitude))
	on_sphere := World_Position(fixed_scale(direction, generation.radius))
	return field_surface_under(generation, on_sphere, millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES)), ""
}

// look <yaw> <pitch> (a bearing from north and a pitch, degrees) or look
// at <x> <y> <z> (metres); answers the stored look.
command_look :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	usage :: "look <yaw> <pitch> | look at <x> <y> <z>"
	request: Developer_Request
	switch {
	case len(arguments) == 4 && arguments[0] == "at":
		target, problem := parse_metres_words(arguments[1:], "a position")
		if problem != "" {
			return command_error("%s", problem)
		}
		request = Developer_Request{action = .Look_At_Field, field_position = target}
	case len(arguments) == 2:
		yaw, yaw_problem := parse_ranged_decimal_word(arguments[0], -360_000, 360_000, "the yaw")
		if yaw_problem != "" {
			return command_error("%s", yaw_problem)
		}
		pitch, pitch_problem := parse_ranged_decimal_word(arguments[1], -89_000, 89_000, "the pitch")
		if pitch_problem != "" {
			return command_error("%s", pitch_problem)
		}
		pitch_units := clamp(millidegrees_to_angle_units(pitch), -FIELD_PITCH_LIMIT, FIELD_PITCH_LIMIT)
		request = Developer_Request{action = .Set_Field_Look, look_angles = {millidegrees_to_angle_units(yaw), pitch_units}}
	case:
		return usage_error(usage)
	}
	if problem := serve_command_request(command_context, request); problem != "" {
		return command_error("%s", problem)
	}
	body := command_context.simulation.players[command_context.player].field
	return command_ok("yaw %.1f pitch %.1f", field_player_bearing_degrees(body), angle_units_to_degrees(body.pitch))
}

command_crouch :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	held, ok := parse_switch_word(len(arguments) == 1 ? arguments[0] : "")
	if !ok {
		return usage_error("crouch <on|off>")
	}
	serve_command_request(command_context, Developer_Request{action = .Hold_Field_Crouch, crouch_held = held})
	return command_ok("crouch %s", arguments[0])
}

// place <machine> <frame> <x> <y> <z> <rotation>: frame 0 is the block
// world's; place_on_frame_for_developer refuses by the frame's rules.
command_field_place :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	usage :: "place <machine> <frame> <x> <y> <z> <rotation>"
	if len(arguments) != 6 {
		return usage_error(usage)
	}
	machine, found := find_machine_id(command_context.content.machines, arguments[0])
	if !found {
		return command_error("unknown machine %q", arguments[0])
	}
	if frame_word, is_number := parse_integer_word(arguments[1]); is_number && frame_word == 0 {
		return command_error(NO_BLOCK_WORLD_PROBLEM)
	}
	frame, problem := parse_ranged_word(arguments[1], 1, int(max(i32)), "the frame")
	if problem != "" {
		return command_error("%s", problem)
	}
	cell, cell_ok := parse_coordinate_words(arguments[2:5])
	if !cell_ok {
		return usage_error(usage)
	}
	rotation: int
	if rotation, problem = parse_ranged_word(arguments[5], 0, 3, "the rotation"); problem != "" {
		return command_error("%s", problem)
	}
	request := Developer_Request{action = .Place_On_Frame, machine = machine, frame = Frame_Id(frame), cell = cell, rotation = u8(rotation)}
	if problem = serve_command_request(command_context, request); problem != "" {
		return command_error("%s", problem)
	}
	return command_ok("placed %s on frame %d at %d %d %d", arguments[0], frame, cell.x, cell.y, cell.z)
}

// Queries.

query_field_player :: proc(command_context: Command_Context) -> Command_Response {
	simulation := command_context.simulation
	player := simulation.players[command_context.player]
	body := player.field
	items := command_context.content.items
	latitude, longitude, _ := field_feet_coordinates(body.position)
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "player\nposition %s\nlatitude %.4f\nlongitude %.4f\nheight %.2f", metres_text(body.position), latitude, longitude, field_height_metres(simulation.world.planet, body.position))
	fmt.sbprintf(&builder, "\nyaw %.1f\npitch %.1f\ncamera %s", field_player_bearing_degrees(body), angle_units_to_degrees(body.pitch), camera_mode_words[body.camera_mode])
	fmt.sbprintf(&builder, "\ncrouching %v\ncrouch_held %v\nflying %v\nno_clip %v\non_ground %v\ncheat_speed %v", body.crouching, body.crouch_held, body.flying, body.no_clip, body.on_ground, simulation.cheat_speed)
	held := selected_hotbar_stack(player)
	held_text := stack_is_empty(held) || int(held.item) >= len(items.items) ? "none" : items.items[held.item].id
	fmt.sbprintf(&builder, "\nhotbar_slot %d\ntool %s\nheld %s", player.selected_hotbar_slot + 1, strings.to_lower(fmt.tprint(body.tool), context.temp_allocator), held_text)
	for item, index in items.items {
		if count := inventory_count(player.inventory, Item_Id(index)); count > 0 {
			fmt.sbprintf(&builder, "\nitem %s %d", item.id, count)
		}
	}
	for stack in simulation.quests.pending_rewards {
		fmt.sbprintf(&builder, "\npending_reward %s %d", items.items[stack.item].id, stack.count)
	}
	return query_response(&builder)
}

// The first alive pod, and its frame.
first_pod :: proc(entities: ^Entities, machines: Machine_Registry) -> (pod: Foundation, frame: Frame, found: bool) {
	for foundation in entities.foundations.entries {
		if foundation.alive && machines.machines[foundation.machine].kind == .Pod {
			frame, found = find_frame(&entities.frames, foundation.frame)
			return foundation, frame, found
		}
	}
	return {}, {}, false
}

query_field_world :: proc(command_context: Command_Context) -> Command_Response {
	simulation := command_context.simulation
	world := &simulation.world
	planet := world.planet
	day_ticks := simulation.day_length_ticks > 0 ? simulation_day_ticks(simulation^) % simulation.day_length_ticks : 0
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "world\nseed %d\ntick %d\nday_ticks %d\nday_length_ticks %d", world.settings.seed, simulation.tick, day_ticks, simulation.day_length_ticks)
	fmt.sbprintf(&builder, "\nplanet %s radius %d sea_level %d spacing %d", planet.id, planet.radius_metres, planet.sea_level_metres, simulation.field.spacing_millimetres)
	fmt.sbprintf(&builder, "\nhome %d %d", planet.home.latitude_degrees, planet.home.longitude_degrees)
	if pod, frame, found := first_pod(&world.entities, command_context.content.machines); found {
		fmt.sbprintf(&builder, "\npod frame %d centre %s", frame.id, metres_text(entity_centre(frame, pod.common)))
	} else {
		strings.write_string(&builder, "\npod none")
	}
	fmt.sbprintf(&builder, "\nframes %d\nfield_chunks %d\nregistered_veins %d\npaused %v", len(world.entities.frames.frames), len(simulation.field.world.chunks), len(world.veins), command_context.control.paused)
	return query_response(&builder)
}

// The sphere's veins whose disc centre lies within the radius (metres)
// of the feet, in registration order, with the generated surface over the
// disc's centre.
query_field_veins :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	radius, problem := query_radius(arguments, DEFAULT_FIELD_VEIN_QUERY_RADIUS_METRES)
	if problem != "" {
		return usage_error("query veins [radius]")
	}
	simulation := command_context.simulation
	veins := command_context.content.veins
	feet := simulation.players[command_context.player].field.position
	generation := simulation.field.world.water_planet.generation
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "veins")
	for vein in simulation.world.veins {
		centre := World_Position(vein.sphere_centre)
		if vein.sphere_radius <= 0 || vein.type >= len(veins.types) || metres_between(feet, centre) > f64(radius) {
			continue
		}
		size := vein.size_class < len(veins.size_class_ids) ? veins.size_class_ids[vein.size_class] : "?"
		latitude, longitude, _ := field_feet_coordinates(centre)
		surface := field_surface_under(generation, centre, 0)
		fmt.sbprintf(&builder, "\nvein %s size %s layer surface latitude %.4f longitude %.4f surface %s", veins.types[vein.type].id, size, latitude, longitude, metres_text(surface))
		fmt.sbprintf(&builder, " radius %.1f distance %.1f remaining %d id %d exhausted %v", f64(vein.sphere_radius) / POSITION_UNITS_PER_METRE, metres_between(feet, surface), vein_remaining_total(vein), vein.id.index, vein.exhausted)
	}
	return query_response(&builder)
}

Field_Entity_Listing :: struct {
	machine: string,
	frame:   Frame,
	common:  Entity_Common,
}

field_entity_listing_before :: proc(first, second: Field_Entity_Listing) -> bool {
	if first.frame.id != second.frame.id {
		return first.frame.id < second.frame.id
	}
	return coordinate_before(first.common.origin, second.common.origin)
}

// The entities with an occupied cell on a frame other than frame 0 whose
// centre lies within the radius (metres) of the feet, by frame and origin.
query_field_entities :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	kind := ""
	rest := arguments
	if len(rest) > 0 {
		if _, is_number := parse_integer_word(rest[0]); !is_number {
			kind, rest = rest[0], rest[1:]
		}
	}
	radius, problem := query_radius(rest, DEFAULT_FIELD_ENTITY_QUERY_RADIUS_METRES)
	if problem != "" {
		return usage_error("query entities [kind] [radius]")
	}
	entities := &command_context.simulation.world.entities
	machines := command_context.content.machines
	feet := command_context.simulation.players[command_context.player].field.position
	seen := make(map[Entity_Handle]bool, context.temp_allocator)
	listings := make([dynamic]Field_Entity_Listing, context.temp_allocator)
	for key, occupant in entities.frames.occupants {
		handle := entity_from_occupant(occupant.handle)
		if key.frame == BLOCK_FRAME || handle in seen {
			continue
		}
		frame, found := find_frame(&entities.frames, key.frame)
		if !found || metres_between(feet, frame_cell_centre(frame, key.cell)) > f64(radius) {
			continue
		}
		seen[handle] = true
		common := entity_common(entities, handle)
		if common != nil && entity_matches_kind(handle, machines.machines[common.machine], kind) {
			append(&listings, Field_Entity_Listing{machine = machines.machines[common.machine].id, frame = frame, common = common^})
		}
	}
	slice.sort_by(listings[:], field_entity_listing_before)
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "entities %d", len(listings))
	for listing in listings {
		origin, size := listing.common.origin, listing.common.size
		fmt.sbprintf(&builder, "\nentity %s frame %d cell %d %d %d size %d %d %d", listing.machine, listing.frame.id, origin.x, origin.y, origin.z, size.x, size.y, size.z)
		fmt.sbprintf(&builder, " rotation %d centre %s", listing.common.rotation, metres_text(entity_centre(listing.frame, listing.common)))
	}
	return query_response(&builder)
}

unit_vector_text :: proc(vector: [3]i64) -> string {
	return fmt.tprintf("%.4f %.4f %.4f", f64(vector.x) / UNIT_VECTOR_ONE, f64(vector.y) / UNIT_VECTOR_ONE, f64(vector.z) / UNIT_VECTOR_ONE)
}

// The frames whose origin lies within the radius (metres) of the feet, by
// id, with their axes and occupied cell count.
query_frames :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	radius, problem := query_radius(arguments, DEFAULT_FRAME_QUERY_RADIUS_METRES)
	if problem != "" {
		return usage_error("query frames [radius]")
	}
	table := &command_context.simulation.world.entities.frames
	feet := command_context.simulation.players[command_context.player].field.position
	listed := make([dynamic]Frame, context.temp_allocator)
	for frame in table.frames {
		if metres_between(feet, frame.origin) <= f64(radius) {
			append(&listed, frame)
		}
	}
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "frames %d", len(listed))
	for frame in listed {
		fmt.sbprintf(&builder, "\nframe %d origin %s pitch %d", frame.id, metres_text(frame.origin), frame.pitch_millimetres)
		fmt.sbprintf(&builder, " right %s up %s forward %s", unit_vector_text(frame.axes[FRAME_RIGHT]), unit_vector_text(frame.axes[FRAME_UP]), unit_vector_text(frame.axes[FRAME_FORWARD]))
		fmt.sbprintf(&builder, " cells %d", frame_cell_count(table, frame.id))
	}
	return query_response(&builder)
}
