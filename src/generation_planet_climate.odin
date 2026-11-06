package game

import "generation_seed"

// The planet's climate (work item 0307, doc/architecture.md, World
// generation): a temperature and a moisture at every point, a pure
// function of the seed, the recorded field (Planet_Climate_Field) and the
// point, in integers only, so the readers that will feed the simulation
// (the biomes, the trees) agree on every machine. Each is two octaves of
// value noise read on the sphere of the radius; the temperature cools by
// the lapse with the height over the sea, so the snow line follows the
// relief. The mesher reads it per vertex for the ground's look
// (world_field_ground_look.odin).

// The second octave's wavelength in thousandths of the first's: not a
// fraction of small numbers, so the two lattices never line up.
CLIMATE_SECOND_OCTAVE_PERMILLE :: 309

Planet_Climate_Sample :: struct {
	temperature_millicelsius: i64,
	moisture_permille:        i64,
}

// Two octaves weighed two to one, within -NOISE_ONE to NOISE_ONE.
planet_climate_noise :: proc(seed: u64, point: [3]i64, wavelength_metres: int) -> i64 {
	wavelength := metres_to_position_units(i64(wavelength_metres))
	first := value_noise(seed, point, wavelength)
	second := value_noise(generation_seed.hash_combine(seed, 1), point, wavelength * CLIMATE_SECOND_OCTAVE_PERMILLE / 1000)
	return (2 * first + second) / 3
}

// The climate at a point on the sphere of the radius (on_sphere, as the
// relief reads it) standing height position units over the sea level;
// the zero sample without a climate.
planet_climate :: proc(generation: Planet_Generation, on_sphere: [3]i64, height: i64) -> Planet_Climate_Sample {
	field := generation.climate
	if field.temperature_wavelength_metres == 0 {
		return {}
	}
	temperature_noise := planet_climate_noise(generation_seed.hash_combine(generation.climate_seed, 0), on_sphere, field.temperature_wavelength_metres)
	moisture_noise := planet_climate_noise(generation_seed.hash_combine(generation.climate_seed, 2), on_sphere, field.moisture_wavelength_metres)
	temperature := i64(field.sea_level_celsius) * 1000 + i64(field.temperature_spread_celsius) * 1000 * temperature_noise / NOISE_ONE - i64(field.lapse_millicelsius_per_metre) * height / POSITION_UNITS_PER_METRE
	moisture := i64(field.moisture_percent) * 10 + i64(field.moisture_spread_percent) * 10 * moisture_noise / NOISE_ONE
	return {temperature, clamp(moisture, 0, 1000)}
}
