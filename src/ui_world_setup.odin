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
	// Work item 0179: an index into the content's planets, one of that
	// planet's radius presets, one of SAMPLE_SPACING_CHOICES_MILLIMETRES.
	planet_choice:        int,
	planet_radius_metres: int,
	sample_spacing_millimetres: int,
	mode:                 World_Mode,
	keep_inventory:       bool,
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
		sample_spacing_millimetres = DEFAULT_SAMPLE_SPACING_MILLIMETRES,
		planet_id = DEFAULT_PLANET_ID,
		mode = .Peaceful,
		keep_inventory = true,
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

// The index of the choice nearest value, the first of two as near.
nearest_choice_index :: proc(choices: []int, value: int) -> int {
	nearest := 0
	for choice, index in choices {
		if abs(choice - value) < abs(choices[nearest] - value) {
			nearest = index
		}
	}
	return nearest
}

// The day length choice nearest a planet's rotation period (0179), in
// seconds against the minute choices.
planet_day_length_choice :: proc(planet: Planet) -> int {
	seconds := make([]int, len(day_length_minute_choices), context.temp_allocator)
	for minutes, index in day_length_minute_choices {
		seconds[index] = minutes * 60
	}
	return nearest_choice_index(seconds, planet.rotation_period_seconds)
}

// planets are the content's: the setup starts on the defaults' planet
// (or the first) at its default radius, with the day as long as the
// planet's rotation (the setting stays and the player may change it).
make_world_setup :: proc(defaults: World_File_Settings, planets: []Planet, name: string, seed: u64) -> World_Setup {
	planet_choice := 0
	for planet, index in planets {
		if planet.id == defaults.planet_id {
			planet_choice = index
		}
	}
	day_length_choice := choice_index(day_length_minute_choices[:], defaults.day_length_seconds / 60, DEFAULT_DAY_LENGTH_CHOICE)
	if len(planets) > 0 {
		day_length_choice = planet_day_length_choice(planets[planet_choice])
	}
	return World_Setup {
		name = make_text_field(name, WORLD_NAME_MAXIMUM_LENGTH),
		seed = make_text_field(fmt.tprint(seed), SEED_MAXIMUM_LENGTH, characters = .Digits),
		veins_infinite = defaults.veins_infinite,
		vein_richness_choice = choice_index(setting_percent_choices[:], defaults.vein_richness_percent, DEFAULT_PERCENT_CHOICE),
		research_cost_choice = choice_index(setting_percent_choices[:], defaults.research_cost_percent, DEFAULT_PERCENT_CHOICE),
		byproducts_lenient = defaults.byproducts_lenient,
		all_recipes_unlocked = defaults.all_recipes_unlocked,
		day_length_choice = day_length_choice,
		planet_choice = planet_choice,
		planet_radius_metres = len(planets) > 0 ? planets[planet_choice].radius_metres : 0,
		sample_spacing_millimetres = defaults.sample_spacing_millimetres,
		mode = defaults.mode,
		keep_inventory = defaults.keep_inventory,
	}
}

// The chosen planet; found is false without planet data. The choice is
// clamped, as a data reload may shorten the list under the screen.
world_setup_planet :: proc(setup: World_Setup, planets: []Planet) -> (planet: Planet, found: bool) {
	if len(planets) == 0 {
		return {}, false
	}
	return planets[clamp(setup.planet_choice, 0, len(planets) - 1)], true
}

// The next planet, at its default radius and its day length.
step_world_setup_planet :: proc(setup: ^World_Setup, planets: []Planet) {
	if len(planets) == 0 {
		return
	}
	setup.planet_choice = next_choice(clamp(setup.planet_choice, 0, len(planets) - 1), len(planets))
	setup.planet_radius_metres = planets[setup.planet_choice].radius_metres
	setup.day_length_choice = planet_day_length_choice(planets[setup.planet_choice])
}

// The preset after the current radius, round the planet's list.
step_world_setup_radius :: proc(setup: ^World_Setup, planets: []Planet) {
	planet, found := world_setup_planet(setup^, planets)
	if !found {
		return
	}
	presets := planet.radius_presets_metres
	current := choice_index(presets, setup.planet_radius_metres, len(presets) - 1)
	setup.planet_radius_metres = presets[next_choice(current, len(presets))]
}

step_world_setup_spacing :: proc(setup: ^World_Setup) {
	choices := SAMPLE_SPACING_CHOICES_MILLIMETRES
	current := choice_index(choices[:], setup.sample_spacing_millimetres, len(choices) - 1)
	setup.sample_spacing_millimetres = choices[next_choice(current, len(choices))]
}

step_world_setup_mode :: proc(setup: ^World_Setup) {
	setup.mode = World_Mode(next_choice(int(setup.mode), len(World_Mode)))
}

// The seed field holds digits only; empty or past the u64 range is invalid.
world_setup_seed :: proc(setup: ^World_Setup) -> (seed: u64, ok: bool) {
	return parse_seed(text_field_text(&setup.seed))
}

randomise_seed :: proc(setup: ^World_Setup) {
	text_field_set(&setup.seed, fmt.tprint(rand.uint64()))
}

// The planet's id and radius are checked against the data when the
// session starts (resolve_world_planet).
world_file_settings_from_setup :: proc(setup: World_Setup, planets: []Planet) -> World_File_Settings {
	planet, _ := world_setup_planet(setup, planets)
	return World_File_Settings {
		veins_infinite = setup.veins_infinite,
		all_recipes_unlocked = setup.all_recipes_unlocked,
		day_length_seconds = day_length_minute_choices[setup.day_length_choice] * 60,
		vein_richness_percent = setting_percent_choices[setup.vein_richness_choice],
		research_cost_percent = setting_percent_choices[setup.research_cost_choice],
		byproducts_lenient = setup.byproducts_lenient,
		sample_spacing_millimetres = setup.sample_spacing_millimetres,
		planet_id = planet.id,
		planet_radius_metres = setup.planet_radius_metres,
		mode = setup.mode,
		keep_inventory = setup.keep_inventory,
	}
}

// The number of a "{name} km" string: 4000 reads "4", 4500 "4.5".
kilometres_number_text :: proc(metres: int) -> string {
	if metres % 1000 == 0 {
		return fmt.tprint(metres / 1000)
	}
	return fmt.tprintf("%.1f", f64(metres) / 1000)
}

// The number of a "{name} m" string: 1000 reads "1", 500 "0.5", 333
// "0.33".
metres_number_text :: proc(millimetres: int) -> string {
	switch {
	case millimetres % 1000 == 0:
		return fmt.tprint(millimetres / 1000)
	case millimetres % 100 == 0:
		return fmt.tprintf("%.1f", f64(millimetres) / 1000)
	}
	return fmt.tprintf("%.2f", f64(millimetres) / 1000)
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
