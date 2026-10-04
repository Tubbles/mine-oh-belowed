package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "model_obj"

// Every range check is written to fail closed: the SJSON reader accepts
// NaN, for which every comparison is false, and a NaN converted to an
// integer differs between x86 and arm64.
//
// The reader of data/models/<model>.collision.sjson (work item 0230,
// doc/content.md, Models): the volumes a model script's collision(b)
// section lists, written by tools/make_models.py, checked against the
// machine's footprint and resolved into model units
// (COLLISION_UNITS_PER_CELL per cell, world_frame_body.odin). A machine
// whose model has no such file has no volumes.

// A sector's angles lie from -360 to 720 degrees (range checked before
// the conversion).
COLLISION_SECTOR_LIMIT_DEGREES :: 720

// As the file writes it: cells of the model's frame (x and z centred on
// the unrotated footprint, y from its bottom, +x the front).
Collision_Volume_Definition :: struct {
	kind:        string,
	axis:        string,
	from:        [3]f64,
	to:          [3]f64,
	radius_from: f64,
	radius_to:   f64,
	shell:       f64,
	sector:      []f64,
}

Collision_File :: struct {
	volumes: []Collision_Volume_Definition,
}

parse_collision_file :: proc(data: []byte, allocator := context.allocator) -> (file: Collision_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

collision_axis :: proc(name: string) -> (axis: int, found: bool) {
	switch name {
	case "x":
		return 0, true
	case "y":
		return 1, true
	case "z":
		return 2, true
	}
	return 0, false
}

// A box shell counts 4, every other volume 1.
collision_definition_count :: proc(definitions: []Collision_Volume_Definition) -> int {
	count := 0
	for definition in definitions {
		count += definition.kind == "box" && definition.shell > 0 ? 4 : 1
	}
	return count
}

// A box's corners; a round's axis span and from plus and minus the larger
// radius on the other two axes (its full turn).
collision_definition_bounds :: proc(definition: Collision_Volume_Definition, axis: int) -> (minimum, maximum: [3]f64) {
	if definition.kind == "box" {
		return definition.from, definition.to
	}
	radius := max(definition.radius_from, definition.radius_to)
	minimum, maximum = definition.from - radius, definition.from + radius
	minimum[axis], maximum[axis] = definition.from[axis], definition.to[axis]
	return minimum, maximum
}

// Inside the footprint plus MODEL_FOOTPRINT_TOLERANCE_CELLS on every
// side, the top included.
collision_bounds_fit :: proc(minimum, maximum: [3]f64, footprint: [3]i32) -> bool {
	tolerance := f64(MODEL_FOOTPRINT_TOLERANCE_CELLS)
	half_width := f64(footprint.x) / 2 + tolerance
	half_depth := f64(footprint.z) / 2 + tolerance
	return minimum.x >= -half_width && maximum.x <= half_width && minimum.z >= -half_depth && maximum.z <= half_depth && minimum.y >= -tolerance && maximum.y <= f64(footprint.y) + tolerance
}

// From the first angle to the second, 0 to under 360 degrees.
collision_sector_span :: proc(sector: []f64) -> f64 {
	span := math.mod(sector[1] - sector[0], 360)
	if span < 0 {
		span += 360
	}
	return span
}

collision_sector_problem :: proc(sector: []f64) -> bool {
	if len(sector) == 0 {
		return false
	}
	if len(sector) != 2 {
		return true
	}
	for angle in sector {
		if !(angle >= -360 && angle <= COLLISION_SECTOR_LIMIT_DEGREES) {
			return true
		}
	}
	return !(collision_sector_span(sector) > 0)
}

collision_box_problem :: proc(definition: Collision_Volume_Definition, axis: int, prefix: string) -> string {
	for index in 0 ..< 3 {
		if !(definition.from[index] < definition.to[index]) {
			return fmt.tprintf("%s is a box whose from is not below its to on every axis", prefix)
		}
	}
	if len(definition.sector) > 0 {
		return fmt.tprintf("%s is a box with a sector", prefix)
	}
	if !(definition.shell >= 0) {
		return fmt.tprintf("%s is a box shell of %.4f cells, not above 0 and under half its size across its axis", prefix, definition.shell)
	}
	if definition.shell > 0 {
		first, second := collision_perpendicular_axes(axis)
		size := definition.to - definition.from
		if !(2 * definition.shell < size[first] && 2 * definition.shell < size[second]) {
			return fmt.tprintf("%s is a box shell of %.4f cells, not above 0 and under half its size across its axis", prefix, definition.shell)
		}
	}
	return ""
}

collision_round_problem :: proc(definition: Collision_Volume_Definition, axis: int, prefix: string) -> string {
	first, second := collision_perpendicular_axes(axis)
	if definition.from[first] != definition.to[first] || definition.from[second] != definition.to[second] || !(definition.from[axis] < definition.to[axis]) {
		return fmt.tprintf("%s is a round whose from and to are not two points along its axis, from below to", prefix)
	}
	if !(definition.radius_from > 0) || !(definition.radius_to > 0) {
		return fmt.tprintf("%s has radius_from %.4f and radius_to %.4f, not both above 0", prefix, definition.radius_from, definition.radius_to)
	}
	if !(definition.shell >= 0 && definition.shell < min(definition.radius_from, definition.radius_to)) {
		return fmt.tprintf("%s has shell %.4f, not 0 to under its smaller radius", prefix, definition.shell)
	}
	if collision_sector_problem(definition.sector) {
		return fmt.tprintf("%s has a sector that is not two angles from -360 to 720 degrees spanning more than 0 and less than 360", prefix)
	}
	return ""
}

// The first problem of a volume, "" for none; each begins with the path
// and the volume's index.
collision_volume_problem :: proc(definition: Collision_Volume_Definition, index: int, path: string, machine_id: string, footprint: [3]i32) -> string {
	prefix := fmt.tprintf("%s: volume %d", path, index)
	if definition.kind != "box" && definition.kind != "round" {
		return fmt.tprintf("%s has kind %q, not box or round", prefix, definition.kind)
	}
	axis, axis_found := collision_axis(definition.axis)
	needs_axis := definition.kind == "round" || definition.shell > 0
	if (definition.axis != "" && !axis_found) || (needs_axis && !axis_found) {
		return fmt.tprintf("%s has axis %q, not x, y or z", prefix, definition.axis)
	}
	problem := definition.kind == "box" ? collision_box_problem(definition, axis, prefix) : collision_round_problem(definition, axis, prefix)
	if problem != "" {
		return problem
	}
	if minimum, maximum := collision_definition_bounds(definition, axis); !collision_bounds_fit(minimum, maximum, footprint) {
		return fmt.tprintf("%s is not inside the footprint of machine %q (%d by %d by %d cells with %.2f of slack)", prefix, machine_id, footprint.x, footprint.z, footprint.y, MODEL_FOOTPRINT_TOLERANCE_CELLS)
	}
	return ""
}

// The count first, then each volume's problem; "" for none.
collision_file_problem :: proc(file: Collision_File, path: string, machine_id: string, footprint: [3]i32) -> string {
	if count := collision_definition_count(file.volumes); count > COLLISION_VOLUME_LIMIT {
		return fmt.tprintf("%s: %d volumes, at most %d (a box shell counts as 4)", path, count, COLLISION_VOLUME_LIMIT)
	}
	for definition, index in file.volumes {
		if problem := collision_volume_problem(definition, index, path, machine_id, footprint); problem != "" {
			return problem
		}
	}
	return ""
}

// Called only on checked values.
collision_units :: proc(cells: f64) -> i64 {
	return i64(math.round(cells * COLLISION_UNITS_PER_CELL))
}

collision_point_units :: proc(point: [3]f64) -> [3]i64 {
	return {collision_units(point.x), collision_units(point.y), collision_units(point.z)}
}

// None for an empty one; else each edge as a unit vector of its angle.
collision_sector :: proc(sector: []f64) -> Collision_Sector {
	if len(sector) == 0 {
		return {}
	}
	edges: [2][2]i64
	for degrees, index in sector[:2] {
		angle := i32(math.round(degrees * ANGLE_UNITS_PER_TURN / 360))
		edges[index] = {fixed_cosine(angle), fixed_sine(angle)}
	}
	return {partial = true, start = edges[0], end = edges[1], wide = collision_sector_span(sector) > 180}
}

// The integer form of collision_definition_bounds.
collision_volume_bound :: proc(volume: Collision_Volume) -> (minimum, maximum: [3]i64) {
	if volume.kind == .Box {
		return volume.from, volume.to
	}
	radius := max(volume.radius_from, volume.radius_to)
	minimum, maximum = volume.from - radius, volume.from + radius
	minimum[volume.axis], maximum[volume.axis] = volume.from[volume.axis], volume.to[volume.axis]
	return minimum, maximum
}

// A box shell's four solid walls on the two axes across its axis, each
// shell thick and as long as the box along the other two axes: the
// -first, +first, -second, +second wall.
collision_box_shell_walls :: proc(box: Collision_Volume, axis: int, shell: i64) -> [4]Collision_Volume {
	first, second := collision_perpendicular_axes(axis)
	walls := [4]Collision_Volume{box, box, box, box}
	walls[0].to[first] = box.from[first] + shell
	walls[1].from[first] = box.to[first] - shell
	walls[2].to[second] = box.from[second] + shell
	walls[3].from[second] = box.to[second] - shell
	return walls
}

with_collision_bound :: proc(volume: Collision_Volume) -> Collision_Volume {
	bounded := volume
	bounded.bound_minimum, bounded.bound_maximum = collision_volume_bound(volume)
	return bounded
}

// Checked definitions in order into model units; a box shell becomes four
// solid boxes in place.
resolve_collision_volumes :: proc(definitions: []Collision_Volume_Definition, allocator := context.allocator) -> []Collision_Volume {
	volumes := make([dynamic]Collision_Volume, 0, collision_definition_count(definitions), allocator)
	for definition in definitions {
		axis, _ := collision_axis(definition.axis)
		volume := Collision_Volume {
			axis = axis,
			from = collision_point_units(definition.from),
			to   = collision_point_units(definition.to),
		}
		if definition.kind == "box" {
			if definition.shell > 0 {
				for wall in collision_box_shell_walls(volume, axis, collision_units(definition.shell)) {
					append(&volumes, with_collision_bound(wall))
				}
				continue
			}
			append(&volumes, with_collision_bound(volume))
			continue
		}
		volume.kind = .Round
		volume.radius_from = collision_units(definition.radius_from)
		volume.radius_to = collision_units(definition.radius_to)
		volume.shell = collision_units(definition.shell)
		volume.sector = collision_sector(definition.sector)
		append(&volumes, with_collision_bound(volume))
	}
	return volumes[:]
}

// Nothing for a machine without a model or without the file. Several
// machines naming one model each read it against their own footprint.
load_machine_collision :: proc(data_directory: string, machine: Machine, allocator := context.allocator) -> (volumes: []Collision_Volume, problem: string) {
	if machine.model == "" {
		return nil, ""
	}
	path := model_obj.collision_file_path(data_directory, machine.model)
	if !os.is_file(path) {
		return nil, ""
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		return nil, fmt.tprintf("%s: cannot read: %v", path, read_error)
	}
	file, parse_error := parse_collision_file(data, context.temp_allocator)
	if parse_error != nil {
		return nil, fmt.tprintf("%s: cannot parse: %v", path, parse_error)
	}
	if problem = collision_file_problem(file, path, machine.id, machine.footprint); problem != "" {
		return nil, problem
	}
	return resolve_collision_volumes(file.volumes, allocator), ""
}

// Every machine in order; the first problem returns.
load_machine_collisions :: proc(registry: ^Machine_Registry, data_directory: string, allocator := context.allocator) -> string {
	for &machine in registry.machines {
		volumes, problem := load_machine_collision(data_directory, machine, allocator)
		if problem != "" {
			return problem
		}
		machine.collision = volumes
	}
	return ""
}
