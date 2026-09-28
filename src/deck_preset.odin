package game

import "core:os"

// The Steam Deck preset (work item 0076). Steam sets SteamDeck=1 in the
// environment of every game it starts on a Deck. On the first start there
// the preset picks the settings the Deck's 1280 by 800 screen and its APU
// want, writes them to the settings file with the marker
// settings.deck_preset_applied, and never applies again: a later start
// finds the marker and leaves the player's choices alone. A --set naming
// one of the preset's keys holds the preset off for that start.

STEAM_DECK_ENVIRONMENT_VARIABLE :: "SteamDeck"
DECK_PRESET_FRAME_RATE_CAP :: 40
DECK_PRESET_UI_SCALE :: 1.1
DECK_PRESET_TEXT_SCALE :: 1.1
DECK_PRESET_KEYS :: [?]string {
	"settings.frame_rate_cap",
	"settings.weather",
	"settings.ui_scale",
	"settings.text_scale",
	"settings.window_mode",
	"settings.deck_preset_applied",
}

// steam_deck is the SteamDeck variable's value, empty when unset.
deck_preset_active :: proc(steam_deck: string, settings: Settings, provenance: Configuration_Provenance) -> bool {
	if steam_deck != "1" || settings.deck_preset_applied {
		return false
	}
	keys := DECK_PRESET_KEYS
	for key in keys {
		if source_of_key_path(provenance, key) == COMMAND_LINE_SOURCE {
			return false
		}
	}
	return true
}

apply_deck_preset :: proc(settings: Settings) -> Settings {
	result := settings
	result.frame_rate_cap = DECK_PRESET_FRAME_RATE_CAP
	result.weather = true
	result.ui_scale = DECK_PRESET_UI_SCALE
	result.text_scale = DECK_PRESET_TEXT_SCALE
	result.window_mode = .Borderless
	result.deck_preset_applied = true
	return result
}

// Runs once at start, before the window opens. The settings file is
// written at once, so the marker is on disk before the first frame; when
// the write fails the preset still holds for this run and is tried again
// on the next start.
apply_deck_preset_at_start :: proc(environment: Configuration_Environment, loaded: ^Loaded_Configuration) {
	steam_deck := os.get_env(STEAM_DECK_ENVIRONMENT_VARIABLE, context.temp_allocator)
	settings := &loaded.configuration.settings
	if !deck_preset_active(steam_deck, settings^, loaded.provenance) {
		return
	}
	settings^ = apply_deck_preset(settings^)
	if problem := write_settings_file(environment, settings^); problem != "" {
		log_printf("error: cannot save the Steam Deck preset: %s", problem)
		return
	}
	log_printf(
		"settings: Steam Deck preset applied (frame rate cap %d, weather on, ui scale %v, text scale %v, borderless)",
		DECK_PRESET_FRAME_RATE_CAP,
		DECK_PRESET_UI_SCALE,
		DECK_PRESET_TEXT_SCALE,
	)
}
