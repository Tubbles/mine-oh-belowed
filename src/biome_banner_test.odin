package game

import "core:testing"

// Advances the banner by steps frames of seconds each in one biome.
run_biome_banner :: proc(banner: Biome_Banner, biome: int, seconds: f32, steps: int) -> Biome_Banner {
	next := banner
	for _ in 0 ..< steps {
		next = advance_biome_banner(next, biome, seconds)
	}
	return next
}

@(test)
test_biome_banner_announces_the_first_biome_after_the_debounce :: proc(t: ^testing.T) {
	banner := run_biome_banner({}, 3, 0.1, 15)
	testing.expect(t, !banner.showing)
	testing.expect_value(t, biome_banner_alpha(banner), 0)
	banner = run_biome_banner(banner, 3, 0.1, 10)
	testing.expect(t, banner.showing)
	testing.expect_value(t, banner.shown, 3)
	testing.expect_value(t, banner.settled.? or_else -1, 3)
}

@(test)
test_biome_banner_ignores_a_short_visit :: proc(t: ^testing.T) {
	banner := Biome_Banner{settled = 2, candidate = 2}
	banner = run_biome_banner(banner, 5, 0.1, 15)
	banner = run_biome_banner(banner, 2, 0.1, 1)
	banner = run_biome_banner(banner, 5, 0.1, 15)
	testing.expect(t, !banner.showing)
	testing.expect_value(t, banner.settled.? or_else -1, 2)
	// Staying on counts towards the debounce from the return.
	banner = run_biome_banner(banner, 5, 0.1, 10)
	testing.expect(t, banner.showing)
	testing.expect_value(t, banner.shown, 5)
}

@(test)
test_biome_banner_fades_and_times_out :: proc(t: ^testing.T) {
	banner := Biome_Banner{settled = 1, candidate = 1}
	banner = run_biome_banner(banner, 4, 0.25, 9)
	testing.expect(t, banner.showing)
	testing.expect_value(t, biome_banner_alpha(banner), 0)
	banner = run_biome_banner(banner, 4, 0.25, 1)
	testing.expect_value(t, biome_banner_alpha(banner), 0.5)
	banner = run_biome_banner(banner, 4, 0.25, 4)
	testing.expect_value(t, biome_banner_alpha(banner), 1)
	banner = run_biome_banner(banner, 4, 0.25, 6)
	testing.expect_value(t, biome_banner_alpha(banner), 0.5)
	banner = run_biome_banner(banner, 4, 0.25, 1)
	testing.expect(t, !banner.showing)
	testing.expect_value(t, biome_banner_alpha(banner), 0)
	// The settled biome stays quiet.
	banner = run_biome_banner(banner, 4, 0.25, 40)
	testing.expect(t, !banner.showing)
}
