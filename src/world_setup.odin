package game

import "core:fmt"
import "core:math/rand"

// The New world screen's values (DESIGN.md, World settings) and how they
// become the settings a world is made with and saved under.

WORLD_NAME_MAXIMUM_LENGTH :: 32
// The digits of the largest u64.
SEED_MAXIMUM_LENGTH :: 20
@(rodata)
setting_percent_choices := [?]int{50, 100, 200, 400}
@(rodata)
day_length_minute_choices := [?]int{5, 10, 20, 40}
DEFAULT_PERCENT_CHOICE :: 1
DEFAULT_DAY_LENGTH_CHOICE :: 2

World_Setup :: struct {
	name:                 Text_Field,
	seed:                 Text_Field,
	veins_infinite:       bool,
	// Indices into setting_percent_choices and day_length_minute_choices.
	vein_richness_choice: int,
	research_cost_choice: int,
	byproducts_lenient:   bool,
	all_recipes_unlocked: bool,
	day_length_choice:    int,
}

// The settings of a world made without the New world screen (--seed), and
// the defaults the screen starts from.
default_world_file_settings :: proc(config: Game_Config) -> World_File_Settings {
	return World_File_Settings {
		veins_infinite = config.veins_infinite,
		all_recipes_unlocked = config.all_recipes_unlocked,
		day_length_seconds = config.day_length_seconds,
		vein_richness_percent = 100,
		research_cost_percent = 100,
	}
}

choice_index :: proc(choices: []int, value, fallback: int) -> int {
	for choice, index in choices {
		if choice == value {
			return index
		}
	}
	return fallback
}

make_world_setup :: proc(defaults: World_File_Settings, name: string, seed: u64) -> World_Setup {
	return World_Setup {
		name = make_text_field(name, WORLD_NAME_MAXIMUM_LENGTH),
		seed = make_text_field(fmt.tprint(seed), SEED_MAXIMUM_LENGTH, digits_only = true),
		veins_infinite = defaults.veins_infinite,
		vein_richness_choice = choice_index(setting_percent_choices[:], defaults.vein_richness_percent, DEFAULT_PERCENT_CHOICE),
		research_cost_choice = choice_index(setting_percent_choices[:], defaults.research_cost_percent, DEFAULT_PERCENT_CHOICE),
		byproducts_lenient = defaults.byproducts_lenient,
		all_recipes_unlocked = defaults.all_recipes_unlocked,
		day_length_choice = choice_index(day_length_minute_choices[:], defaults.day_length_seconds / 60, DEFAULT_DAY_LENGTH_CHOICE),
	}
}

// The seed field holds digits only; empty or past the u64 range is invalid.
world_setup_seed :: proc(setup: ^World_Setup) -> (seed: u64, ok: bool) {
	return parse_seed(text_field_text(&setup.seed))
}

randomise_seed :: proc(setup: ^World_Setup) {
	text_field_set(&setup.seed, fmt.tprint(rand.uint64()))
}

world_file_settings_from_setup :: proc(setup: World_Setup) -> World_File_Settings {
	return World_File_Settings {
		veins_infinite = setup.veins_infinite,
		all_recipes_unlocked = setup.all_recipes_unlocked,
		day_length_seconds = day_length_minute_choices[setup.day_length_choice] * 60,
		vein_richness_percent = setting_percent_choices[setup.vein_richness_choice],
		research_cost_percent = setting_percent_choices[setup.research_cost_choice],
		byproducts_lenient = setup.byproducts_lenient,
	}
}

world_settings_from_file :: proc(seed: u64, settings: World_File_Settings) -> World_Settings {
	return World_Settings {
		seed = seed,
		veins_infinite = settings.veins_infinite,
		vein_richness_percent = settings.vein_richness_percent,
		research_cost_percent = settings.research_cost_percent,
		byproducts_lenient = settings.byproducts_lenient,
	}
}

next_choice :: proc(choice, count: int) -> int {
	return (choice + 1) % count
}

// 50 reads "0.5x", 200 reads "2x".
percent_multiplier_text :: proc(percent: int) -> string {
	if percent % 100 == 0 {
		return fmt.tprintf("%dx", percent / 100)
	}
	return fmt.tprintf("%.1fx", f64(percent) / 100)
}

// The name a new world starts with: the default name, numbered like the
// save directory would be when a save of that name exists.
default_new_world_name :: proc(base, saves_directory: string, saves_found: bool) -> string {
	if !saves_found {
		return base
	}
	return unused_world_directory_name(saves_directory, sanitize_world_name(base, context.temp_allocator), context.temp_allocator)
}
