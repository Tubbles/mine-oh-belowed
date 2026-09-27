package game

import "core:math"

// The biome banner (work item 0058): once the biome under the player has
// changed and stayed changed for BIOME_BANNER_DEBOUNCE_SECONDS, its name
// fades in at top centre, below the brownout warning's line, shows for
// BIOME_BANNER_SECONDS in all and fades out. The first biome of a world is
// announced the same way. A pure state machine over the frame time: it is
// rendering state, not simulation, and pauses while a screen is open.

BIOME_BANNER_DEBOUNCE_SECONDS :: 2.0
BIOME_BANNER_SECONDS :: 3.0
// At the start and at the end of BIOME_BANNER_SECONDS.
BIOME_BANNER_FADE_SECONDS :: 0.5

// The zero value has announced nothing yet.
Biome_Banner :: struct {
	// The biome last announced.
	settled:           Maybe(int),
	// The biome under the player when it differs from the settled one, and
	// for how long it has.
	candidate:         int,
	candidate_seconds: f32,
	// The biome on the banner, and how long the banner has shown.
	shown:             int,
	shown_seconds:     f32,
	showing:           bool,
}

advance_biome_banner :: proc(banner: Biome_Banner, biome: int, seconds: f32) -> Biome_Banner {
	next := banner
	if next.showing {
		next.shown_seconds += seconds
		next.showing = next.shown_seconds < BIOME_BANNER_SECONDS
	}
	if settled, has_settled := banner.settled.?; has_settled && biome == settled {
		next.candidate_seconds = 0
		return next
	}
	if biome != banner.candidate {
		next.candidate = biome
		next.candidate_seconds = 0
		return next
	}
	next.candidate_seconds += seconds
	if next.candidate_seconds < BIOME_BANNER_DEBOUNCE_SECONDS {
		return next
	}
	next.settled = biome
	next.candidate_seconds = 0
	next.shown = biome
	next.shown_seconds = 0
	next.showing = true
	return next
}

// 0 to 1: fading in, fully shown, fading out; 0 without a banner.
biome_banner_alpha :: proc(banner: Biome_Banner) -> f32 {
	if !banner.showing {
		return 0
	}
	fade_in := banner.shown_seconds / BIOME_BANNER_FADE_SECONDS
	fade_out := (BIOME_BANNER_SECONDS - banner.shown_seconds) / BIOME_BANNER_FADE_SECONDS
	return clamp(min(fade_in, fade_out), 0, 1)
}

// Advances the banner with the biome under the player and draws it.
draw_biome_banner :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	banner, generator, player := screen_context.biome_banner, screen_context.generator, screen_context.player
	if banner == nil || generator == nil || player == nil {
		return
	}
	biome := sample_column(generator, i32(math.floor(player.position.x)), i32(math.floor(player.position.z))).biome
	banner^ = advance_biome_banner(banner^, biome, state.frame_seconds)
	alpha := biome_banner_alpha(banner^)
	if alpha <= 0 || banner.shown >= len(generator.biomes) {
		return
	}
	safe := ui_safe_area(state)
	color := UI_TEXT_COLOR
	color.a = u8(f32(color.a) * alpha)
	area := Ui_Rectangle{safe.x, safe.y + 2 * UI_ROW_HEIGHT, safe.width, UI_ROW_HEIGHT}
	draw_text(state, area, text(generator.biomes[banner.shown].definition.name_key), UI_HEADING_TEXT_SIZE, .Centre, color)
}
