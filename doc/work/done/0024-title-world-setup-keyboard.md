# 0024 Title screen, world setup, on-screen keyboard

Status: implemented
Milestone: M5

## Goal

The game starts at a title screen instead of straight into a world: Continue, New world, Load, Settings, Quit. New world asks for a name through the on-screen keyboard and offers the world settings. Load lists saved worlds.

## Deliverables

- Title screen as the first screen, with the world rendered behind it as a slowly turning view of a generated area or a plain backdrop (say which).
- New world screen: name field with the on-screen keyboard widget from `doc/ui.md` (QWERTY grid, focus and pointer, shift, space, backspace, done; physical keyboard types into the same field), seed field (random by default, editable digits), and the world settings from DESIGN.md: vein finiteness, vein richness, research cost multiplier, byproduct strictness (stored, no effect yet), all recipes unlocked at start, day length. Settings are written into `world.sjson` and read by the simulation where they already exist (veins infinite, all recipes unlocked, day length; richness and research cost wire into generation and lab cost).
- Load screen: saved worlds sorted by last played with name, seed and play time, Confirm loads, the context action deletes after a confirmation dialog.
- Continue loads the most recently played world.
- Quit to title from the pause menu (saving first).
- `--seed` and `--load` keep working for development; `--debug-terrain` skips the title.
- Tests: keyboard widget input handling (typing, shift, backspace, done), seed field validation, world settings round trip to `world.sjson`, save listing order.

## Verify

- Builds and tests pass.
- User: from the couch, create a world named with the on-screen keyboard using only the controller, play, quit to title, and continue it.

## Notes

Implemented 2026-09-27. Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (372 tests, 13 new), `./build.sh`, `./build.sh release`, `--version`. With `MINE_OH_BELOWED_SAVES` on a scratch directory, `--seed=5 --name=Smoke` found the spawn and wrote `Smoke/world.sjson` (with the new settings) before stopping at the missing display, `--load=Smoke` loaded it, and no arguments went to the title path and stopped at the window.

Code: `session.odin` (`Session`, `Session_Plan`, `start_session`, `end_session`, `save_session`, plan builders), `world_setup.odin` (New world values, choices, conversions, default name), `text_input.odin` (text field and keyboard logic), `ui_keyboard.odin` (text field widget, key grid), `save_list.odin` (listing, newest, delete, play time, dates), `ui_title.odin` (`Title_State`, title, New world, Load, delete confirmation), with changes to `loop.odin`, `main.odin`, `ui_core.odin`, `ui_screens.odin`, `ui_input.odin`, `input_actions.odin`, `input_raylib.odin`, `diagnostics.odin`, `save_world.odin`, `world_vein.odin`, `generation.odin`, `generation_veins.odin`, `technology.odin`, `render_chunks.odin`, `data/strings/en.sjson`. Tests in `text_input_test.odin` and `world_setup_test.odin`.

### Deviations

- The title shows a plain backdrop in the day sky colour with the game name and version, no world behind it: a generated view would need a session (streaming, renderer meshes).
- `run_game` creates the window, renderer, UI and input once; a heap allocated `Session` holds the simulation, a copy of the generator, streaming, the save location, the accumulators and the two browsers. The generator data (biomes, vein tables) is loaded once in `main` and each session copies it with its own seed, richness and landing pad (`session_generator`), so nothing is reloaded or leaked per world. Quitting to the title saves, stops streaming, destroys the simulation and drops every chunk mesh (`unload_all_chunk_meshes`).
- Session changes (start, load, quit to title) are requests the menus set on `Title_State.request`; the frame loop handles them after the frame (`apply_session_request`). A world that cannot be made or loaded leaves the menus showing with a toast.
- Command line worlds are still started before the window opens, so spawn and load problems show on stderr without a display. Every new world with saving on (title or `--seed`/`--name`) saves at once.
- Vein richness and research cost are stored as percents (50, 100, 200, 400) in `World_Settings` and `world.sjson` (`vein_richness_percent`, `research_cost_percent`), plus `byproducts_lenient`. A `world.sjson` without them (0023 saves) loads at 100 percent; values outside 1 to 1000 are refused. Richness multiplies the units in `place_vein` through `Generator.vein_richness_percent`. Research cost makes a per session copy of the technology registry with scaled pack counts (`scaled_technology_registry`, rounded up, at least 1), so labs, the technology screen and diagnostics all see the scaled cost without new parameters; the content fingerprint covers ids only, so saves are unaffected.
- `game.sjson`'s `all_recipes_unlocked`, `veins_infinite` and `day_length_seconds` are now only the defaults the New world screen starts from (and what `--seed` uses). `--unlock-all` still unlocks everything in any new world.
- Keyboard: rows of digits, `qwertyuiop`, `asdfghjkl`, `zxcvbnm`, a symbols row (`-_.`), then Shift, Space, Delete, Done. While the keyboard is open the New world panel shows only the edited field and the keys, so focus cannot leave the keys; B, X, Y and Pause belong to the keyboard (tooltip toggle and screen Back are suppressed). A physical keyboard types through raylib's character queue (`Raw_Keyboard.text`); in a frame with physical typing the button meanings are ignored, since F, R, Q, E and Backspace also fire actions. Physical Backspace deletes and Enter is done; Escape is done like B. Shift is a toggle (caps lock), not one shot. Name at most 32 characters, seed at most 20 digits. Text is printable ASCII only.
- Choices step forward on Confirm and wrap; there is no step back.
- Dates on the Load screen use the local time zone from `core:time/timezone` (UTC when it cannot be loaded). Play time is the saved tick as h:mm of simulated time.
- The delete confirmation declares No first, so it holds the focus when the dialog opens.
- Saves whose world.sjson cannot be read (newer format, malformed) are left out of the list rather than shown as broken.

### Not verified

Everything visual and the feel: title layout, the keyboard grid size and focus movement across rows of different widths, the pointer on the keys, physical typing (character queue, key repeat of letters works, Backspace does not repeat), Load rows fitting at 720p (the row is one long string), the confirmation dialog, toasts on the title, the cursor mode switching between title and world, quit to title and continue from the couch, and mesh cleanup between worlds on the GPU.

### Open questions

- Should Shift be one shot (off after the next letter), as phone keyboards do?
- Should choices step backwards with left and right (they are single widgets now)?
- The Load row as one string is crude; a column layout per row would read better.
- `doc/ui.md` (keyboard buttons, physical typing rule, title backdrop), `doc/architecture.md` (Session and the application states) and `DESIGN.md` World settings (percent choices) should describe the above; this run could not touch them.
