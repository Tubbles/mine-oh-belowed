# 0076 Steam Deck verification

Status: todo
Milestone: M11

## Goal

The Steam Deck is a supported target (user, 2026-09-27). The game must hold its frame rate on the Deck's APU at 1280 by 800, its UI must fit and read at arm's length, and the Deck's built in pads, gyro and grips must work through Steam Input the way the couch does.

## Deliverables

- Performance: the benchmark (0050) run on a Deck, and the rendering settings (shadows, weather particles, view distance) tuned for a Deck preset chosen automatically when the device is a Deck (`SteamDeck=1` in the environment). The frame rate cap setting itself comes from 0080 (Off, 30, 40, 60 and up); the Deck preset picks its value.
- UI: the audit's 1280 by 800 entries stay green, text sizes checked at arm's length, the safe area for the Deck's screen.
- Controls: SDL's Steam Deck HIDAPI driver behind the same launcher override, pads, gyro (from Steam's layout, 0044 notes) and the four grips mapped like the Steam Controller's; verified in Game Mode on the device.
- A Deck section in `doc/input.md` and `doc/build.md` (installing the play build on a Deck over SSH).

## Verify

- Builds and tests pass.
- User: a full chapter 1 on the Deck at a steady frame rate with the built in controls.

## Notes

Implementation pointers (main agent, 2026-09-28). Lands last, after 0050 gives the benchmark numbers; the device work is the user's.

- Deck preset: `deck_preset_active(environment) -> bool` (a new `src/deck_preset.odin`, pure, tested) is true when `SteamDeck=1` is in the environment and no `--set` names the settings it would change; on the first start on a Deck (no `90-settings.sjson` yet, or one without the marker key `deck_preset_applied = true` which the preset writes) the preset sets `frame_rate_cap` 40, `shadows` off, `weather` on, `ui_scale` 1.1, `text_scale` 1.1, `window_mode` borderless, and logs one line; a later start leaves the player's choices alone.
- The audit's 1280 by 800 entries stay in the matrix (they are), with the text scale 1.1 added; the safe area for the Deck's screen is the existing safe area, checked visually by the user.
- Controls: the launcher already carries the SDL override; the Deck's own pads, gyro and grips go through Steam Input's virtual pad plus the Steam layout for the gyro as the couch does (0044 notes); a `doc/input.md` section says what to set in the Deck's layout (gyro to mouse, the grips to the same actions as the Steam Controller's) and a `doc/build.md` section says how to copy a play build to the Deck over SSH (`tools/install_play_build.sh` gains a `--target user@host:path` that runs the same install over ssh and rsync) and add the shortcut with `tools/add_steam_shortcut.py`.
- The benchmark (0050) is run on the Deck by the user with `--benchmark=4`; the numbers go to `doc/content.md` "Learned from couch tests" next to the couch machine's.
- Tests: the preset decision per environment and settings state, the marker key round trip, the audit at text scale 1.1 and 1280 by 800.
- Docs: `doc/input.md`, `doc/build.md`, `doc/ui.md` (the preset), `doc/log/<date>.md`, this item's Status and Notes.

Files a subagent may touch: new `src/deck_preset.odin` and `src/deck_preset_test.odin`, `src/configuration.odin`, `src/configuration_output.odin`, `src/configuration_test.odin`, `src/main.odin` or wherever the configuration is resolved at start, `src/ui_audit_test.odin`, `tools/install_play_build.sh`, the docs above, this file.
