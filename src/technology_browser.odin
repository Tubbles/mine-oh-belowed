package game

import "core:fmt"

// The pure part of the technology screen (doc/ui.md): the list is the
// technologies sorted by name, optionally without the researched ones, and
// jumps by letter like the recipe browser (recipe_position_for_letter).
// ui_technologies.odin draws it.

Technology_Filter :: struct {
	hide_researched: bool,
}

technology_display_names :: proc(technologies: Technology_Registry, allocator := context.allocator) -> []string {
	names := make([]string, len(technologies.technologies), allocator)
	for _, index in technologies.technologies {
		names[index] = technology_name(technologies, index)
	}
	return names
}

// The technologies in the given order (by name) that pass the filter.
filter_technologies :: proc(technologies: Technology_Registry, unlocks: Recipe_Unlocks, order: []int, filter: Technology_Filter, allocator := context.allocator) -> []int {
	visible := make([dynamic]int, 0, len(order), allocator)
	for technology in order {
		if filter.hide_researched && technology_status(technologies, unlocks, technology) == .Researched {
			continue
		}
		append(&visible, technology)
	}
	return visible[:]
}

// Units times seconds per unit in a speed 1 lab.
technology_total_seconds :: proc(technology: Technology) -> f32 {
	return f32(technology.pack_count) * f32(technology.milliseconds_per_pack) / 1000
}

@(rodata)
technology_status_keys := [Technology_Status]string {
	.Researched = "technologies_status_researched",
	.Available  = "technologies_status_available",
	.Locked     = "technologies_status_locked",
}

// "10 × 10 s" per the content tables, and the pack items. units is the
// cost of the next research (technology_next_cost). The sign lives in the
// string table, so every font loads its glyph (collect_code_points).
technology_cost_text :: proc(technology: Technology, units: int, items: Item_Registry) -> string {
	seconds := f32(technology.milliseconds_per_pack) / 1000
	line := replace_message_mark(text("technologies_cost_line"), "{count}", fmt.tprint(units))
	line = replace_message_mark(line, "{seconds}", fmt.tprintf("%.0f", seconds))
	return replace_message_mark(line, "{packs}", pack_names_text(technology.science_packs, items))
}

// "Level 2" for an infinite technology with levels done, else "".
technology_level_text :: proc(technology: Technology, level: u32) -> string {
	if !technology.infinite || level == 0 {
		return ""
	}
	return fmt.tprintf("%s %d", text("technologies_level"), level)
}

pack_names_text :: proc(packs: []Item_Id, items: Item_Registry) -> string {
	result := ""
	for pack, index in packs {
		result = index == 0 ? item_name(items, pack) : fmt.tprintf("%s, %s", result, item_name(items, pack))
	}
	return result
}

research_progress_text :: proc(research: Research_State, technologies: Technology_Registry) -> string {
	if !research.queued {
		return ""
	}
	return fmt.tprintf("%d / %d", research.units_done, queued_research_cost(research, technologies))
}
