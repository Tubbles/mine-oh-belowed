package game

import "core:encoding/json"
import "core:fmt"

// Fluid prototypes from data/fluids.sjson (doc/fluids.md), resolved to a
// dense Fluid_Id after the items. Fluids are never items: they live in
// the litre buffers of pipes and machine ports (fluid_network.odin).

FLUIDS_FILE_NAME :: "fluids.sjson"

// Dense index into Fluid_Registry.fluids.
Fluid_Id :: distinct u16

NO_FLUID :: Fluid_Id(max(u16))

// Liquids flow only to the same height or lower, gases fill any volume.
Fluid_Phase :: enum u8 {
	Liquid,
	Gas,
}

@(rodata)
fluid_phase_names := [Fluid_Phase]string {
	.Liquid = "liquid",
	.Gas    = "gas",
}

// What a port admits beside its fluid filter: any fluid, only one phase
// (the flare stack takes gases only), or only gases with a fuel value (the
// combustion generator, so steam never sits in its port).
Fluid_Phase_Filter :: enum u8 {
	Any,
	Liquid,
	Gas,
	Burnable_Gas,
}

@(rodata)
fluid_phase_filter_names := [Fluid_Phase_Filter]string {
	.Any          = "",
	.Liquid       = "liquid",
	.Gas          = "gas",
	.Burnable_Gas = "burnable_gas",
}

// As written in the file, before validation.
Fluid_Definition :: struct {
	id:                        string,
	name_key:                  string,
	phase:                     string,
	color:                     [3]int,
	fuel_kilojoules_per_litre: int,
}

Fluids_File :: struct {
	fluids: []Fluid_Definition,
}

// fuel_kilojoules_per_litre is the energy a generator gets from burning a
// litre, 0 for a fluid that does not burn (work item 0031 sets it, the
// combustion generator of 0032 reads it).
Fluid :: struct {
	id:                        string,
	name_key:                  string,
	phase:                     Fluid_Phase,
	color:                     [3]u8,
	fuel_kilojoules_per_litre: u32,
}

Fluid_Registry :: struct {
	fluids: []Fluid,
}

parse_fluids_file :: proc(data: []byte, allocator := context.allocator) -> (file: Fluids_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

parse_fluid_phase :: proc(name: string) -> (phase: Fluid_Phase, found: bool) {
	for candidate in Fluid_Phase {
		if fluid_phase_names[candidate] == name {
			return candidate, true
		}
	}
	return .Liquid, false
}

validate_fluid_definition :: proc(definitions: []Fluid_Definition, index: int) -> string {
	definition := definitions[index]
	if definition.id == "" || definition.name_key == "" {
		return fmt.tprintf("fluid %d needs an id and a name_key", index)
	}
	for other in definitions[:index] {
		if other.id == definition.id {
			return fmt.tprintf("fluid id %q is defined twice", definition.id)
		}
	}
	if _, found := parse_fluid_phase(definition.phase); !found {
		return fmt.tprintf("fluid %q has unknown phase %q", definition.id, definition.phase)
	}
	for channel in definition.color {
		if channel < 0 || channel > 255 {
			return fmt.tprintf("fluid %q has a colour channel outside 0 to 255", definition.id)
		}
	}
	if definition.fuel_kilojoules_per_litre < 0 {
		return fmt.tprintf("fluid %q has a negative fuel_kilojoules_per_litre", definition.id)
	}
	return ""
}

resolve_fluid_registry :: proc(file: Fluids_File, allocator := context.allocator) -> (registry: Fluid_Registry, problem: string) {
	if len(file.fluids) >= int(NO_FLUID) {
		return {}, fmt.tprintf("%d fluids exceed the limit of %d", len(file.fluids), int(NO_FLUID) - 1)
	}
	for _, index in file.fluids {
		if problem = validate_fluid_definition(file.fluids, index); problem != "" {
			return {}, problem
		}
	}
	registry.fluids = make([]Fluid, len(file.fluids), allocator)
	for definition, index in file.fluids {
		phase, _ := parse_fluid_phase(definition.phase)
		color := definition.color
		registry.fluids[index] = Fluid {
			id                        = definition.id,
			name_key                  = definition.name_key,
			phase                     = phase,
			color                     = {u8(color.r), u8(color.g), u8(color.b)},
			fuel_kilojoules_per_litre = u32(definition.fuel_kilojoules_per_litre),
		}
	}
	return registry, ""
}

destroy_fluid_registry :: proc(registry: Fluid_Registry, allocator := context.allocator) {
	delete(registry.fluids, allocator)
}

find_fluid_id :: proc(registry: Fluid_Registry, id: string) -> (fluid: Fluid_Id, found: bool) {
	for candidate, index in registry.fluids {
		if candidate.id == id {
			return Fluid_Id(index), true
		}
	}
	return NO_FLUID, false
}

// Ids outside the table (NO_FLUID included) are liquids, which never
// matters: a network without a fluid moves nothing.
fluid_is_gas :: proc(registry: Fluid_Registry, fluid: Fluid_Id) -> bool {
	return int(fluid) < len(registry.fluids) && registry.fluids[fluid].phase == .Gas
}

phase_filter_admits :: proc(filter: Fluid_Phase_Filter, registry: Fluid_Registry, fluid: Fluid_Id) -> bool {
	switch filter {
	case .Liquid:
		return !fluid_is_gas(registry, fluid)
	case .Gas:
		return fluid_is_gas(registry, fluid)
	case .Burnable_Gas:
		return fluid_is_gas(registry, fluid) && registry.fluids[fluid].fuel_kilojoules_per_litre > 0
	case .Any:
	}
	return true
}

fluid_name :: proc(registry: Fluid_Registry, fluid: Fluid_Id) -> string {
	if int(fluid) >= len(registry.fluids) {
		return text("fluid_none")
	}
	return text(registry.fluids[fluid].name_key)
}

load_fluid_registry :: proc(data_directory: string, allocator := context.allocator) -> (registry: Fluid_Registry, ok: bool) {
	data, path := read_logged_data_file(data_directory, FLUIDS_FILE_NAME) or_return
	file, parse_error := parse_fluids_file(data, allocator)
	if parse_error != nil {
		log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	registry, problem = resolve_fluid_registry(file, allocator)
	if problem != "" {
		log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}
