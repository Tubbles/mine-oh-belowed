# 0074 Accessibility

Status: implemented
Milestone: M11

## Goal

Text size, a colour blind safe palette for markers and map, reduced motion (no bob, no weather particles, no flicker), and holds versus toggles for sneak and sprint.

## Deliverables

- Settings for text scale, palette, reduced motion, hold or toggle for sneak and sprint; the bottleneck markers and the map legend redraw with the palette.
- Tests: settings round trip, palette applied to marker colours.

## Verify

- Builds and tests pass.
- User: Switch each on the couch.

## Notes

Implementation pointers (main agent, 2026-09-28), decisions taken so the item is unambiguous. Lands after 0073 (the kick) and 0066 (the bob) and 0063 (the weather setting) it folds into one rule.

- Settings (`src/settings.odin`, `src/configuration.odin`, `src/configuration_test.odin`, a new Accessibility tab on the settings screen in `src/ui_screens.odin`, strings): `text_scale` (0.8 to 1.6, default 1, multiplying every text size the UI draws on top of the UI scale, `src/ui_core.odin` where sizes resolve to pixels; the audit runs its matrix at 1 and at 1.6), `palette` (`default` or `colour_blind`: the bottleneck marker colours and the map's marker and legend colours come from a palette table in `data/ui/theme.sjson` (0071) with a second set safe for deuteranopia and protanopia (blue, orange, black, white, distinct by lightness too), `Marker_Colour` in `src/render_entities.odin` and the map in `src/ui_map.odin` read through the palette), `reduced_motion` (off by default; on, it forces the head bob off, the sprint kick to 0, the weather particles and sway and cloud shadows off (the weather look reads it as the weather setting off), the torch flame and the focus pulse still, and the Mission Control reveal instant), `sneak_hold` and `sprint_hold` (`toggle` or `hold`; the player's sneak is a hold today and sprint a toggle on the stick click: the setting decides in `update_sprinting` and the sneak handling in `src/player.odin`, read through the input frame so the simulation stays pure of settings: the input layer applies them, `apply_look_settings` is the pattern).
- Tests: the configuration round trips and refusals, the text scale in the pixel size, the palette applied to every marker colour (no two markers share a colour in either palette), the reduced motion rule over each thing it stills as pure checks, the hold and toggle rules, the UI audit at text scale 1.6 and with the new tab.
- Docs: `doc/ui.md` (the tab and each setting), `doc/input.md` (hold and toggle), `doc/log/2026-09-28.md`, this item's Status and Notes.

Files a subagent may touch: `src/settings.odin`, `src/configuration.odin`, `src/configuration_test.odin`, `src/ui_screens.odin`, `src/ui_core.odin`, `src/ui_theme.odin` (the palette table), `src/ui_map.odin`, `src/render_entities.odin`, `src/render_weather.odin`, `src/render_player.odin`, `src/player_animation.odin`, `src/ui_mission_control.odin`, `src/player.odin`, `src/player_test.odin`, `src/input_frame.odin` or wherever the input frame carries the toggles, `src/ui_audit_test.odin`, `data/ui/theme.sjson`, `data/strings/en.sjson`, the docs above, this file.

Implemented: `src/settings.odin` (the five settings, `Hold_Mode`, `TEXT_SCALE_RANGE`, `apply_hold_settings`), `src/configuration.odin` (the text scale's range check), `src/configuration_test.odin` (round trip and refusals), `src/ui_screens.odin` and `data/strings/en.sjson` (the Accessibility tab), `src/ui_core.odin` (`Ui_Accessibility`, the text scale in measuring and in `ui_end`, the still focus pulse), `src/ui_theme.odin` and `data/ui/theme.sjson` (`Marker_Palette`, `Palette_Color`, the `palettes` table and its parsing, `map_dot_color`), `src/render_entities.odin` (`bottleneck_marker_colors`), `src/ui_map.odin` (records, player, dots and legend from the palette), `src/render_weather.odin` (`weather_motion_enabled`), `src/player_animation.odin` (`head_bob_enabled`), `src/render_player.odin` (`sprint_kick_degrees`, `flicker_seconds`), `src/ui_mission_control.odin` (`instant_reveal`), `src/input_actions.odin` (the frame's `sneak_toggles` and `sprint_holds`), `src/player.odin` (`update_sneaking`, `with_sneaking`, `Player.sneaking`, the sprint hold), `src/player_test.odin`, `src/ui_audit_test.odin` (text scales 1 and 1.6, the fifth tab), `doc/ui.md`, `doc/input.md`, `doc/log/2026-09-28.md`. Outside the list: `src/loop.odin` (the call sites), `src/ui_theme_test.odin` (the shipped key count) and the new `src/accessibility_test.odin`; decisions and the text height limit at 1.6 are in the log. 947 tests pass (936 before).
