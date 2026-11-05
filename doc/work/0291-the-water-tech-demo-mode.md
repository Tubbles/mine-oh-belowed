# 0291: The water tech demo mode

Status: todo (2026-11-05)

Milestone: side quest for M14 (the ground game): a couch build that drops straight onto a planet to judge the water models of the browser study (`work/research` of the water-demos session, 2026-11-03 to 05: the body model and the cellular rule with teleport pressure, both with a wave layer and a thin-sheet mesher), with the player walking, digging, raising, adding and removing water and placing pumps, under a sun and a torchlight. The items: 0291 (this, the mode, the menu, the demo kit, the couch script), 0292 (teleport pressure and the dead band), 0293 (water bodies), 0294 (the water's look: sheet, radial plane, waves), 0295 (water tools and pumps), 0296 (jetpack, cheat mode), 0297 (sun and torchlight).

## Goal

`./update-and-run.sh` on the couch (a Steam shortcut in game mode) pulls `main`, builds the release and launches the game into a small gamepad menu: water model (Teleport pressure, Bodies), planet radius (4, 8, 16 km), start point (Home, Spring), Start. Start drops the player standing at the chosen point on a `home` planet of that radius with no arrival fall, no save, no quests, holding a demo kit that digs any material and raises ground without cost, with the HUD and the normal field controls. Back (B) on the menu returns to the title; Pause in the world offers Quit to title.

## Controls

- Menu: the title gains a button "Water tech demo" between New world and Load; the screen `Tech_Demo` holds three `ui_choice` rows (water model, radius, start point) and Start, navigated as every screen (D-pad, Confirm A, Back B).
- World: the field bindings as they are (`data/bindings.sjson`): Mine R2 digs, Place L2 raises or places the held item, hotbar on D-pad left/right and the shoulders, Next_Brush Y, Jump A, Sneak B, Sprint L3, Pause Start. The demo kit fills the hotbar: 1 iron pickaxe (digs every material but bedrock in the demo), 2 dirt (unlimited in the demo), 3 water bucket (0295), 4 drain bucket (0295), 5 pump (0295), 6 torch. No binding changes in this item; 0296 and 0297 add theirs.
- Command line: `--tech-demo[=model,radius,start]` starts the world directly with the menu's defaults (model `teleport`, radius 8000, start `spring`), so the Steam shortcut's LaunchOptions can skip the title; `--tech-demo` alone opens the title with the tech demo screen pushed.

## Change

- `Session_Request_Kind.Tech_Demo` and `Screen.Tech_Demo` (`ui_title.odin`, `ui_screens.odin`, `ui_core.odin`), served in `apply_session_request` (`loop.odin`) by `start_tech_demo_session` (`session.odin`, after the pattern of `start_planet_preview_session`: `default_world_file_settings`, planet `home`, the chosen radius, `new_world_plan` with saves "" so nothing is saved, `start_session`, `arrival = {}`), entering the normal loop so SDL3 input and the HUD are the real ones.
- `World_File_Settings.water_model` (`save_world.odin`: `teleport` default, `bodies`) read by 0293; `tech_demo` flag on `Simulation_Content.field` (`simulation_field.odin`) that `field_diggable_materials` and `drain_field_place` / `drain_field_dig` honour (dig everything but bedrock, no credit, no debit); the spawn at the spring: the first air sample over the spring's surface point, `spawn_field_player_at` beside `field_pod_spawn`; the demo kit through a `tech_demo_items` list in `data/game.sjson` given as `give_planet_preview_items` does.
- `--tech-demo` in `Command_Line` (`main.odin`), `doc/commands.md`.
- `update-and-run.sh` at the repository root: `git pull --ff-only`, `./build.sh release`, `exec build/mine-oh-belowed --tech-demo "$@"` with `MINE_OH_BELOWED_GAMESCOPE` honoured as the play launcher does; it refuses to run with uncommitted changes in `src/` or `data/` and prints why. `tools/add_steam_shortcut.py --tech-demo` writes a second shortcut "Mine oh Belowed: water tech demo" whose target is the script. `doc/build.md` (Steam, the tech demo), `doc/README.md` index.
- HUD: the debug overlay's water line (total water, awake samples, bodies when 0293 is in) is on by default in the tech demo.

## Verify

- `./build.sh check`, `check-android`, `test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- A test starts a tech demo session at 4000 m at the spring and asserts: no arrival, the player stands within 2 m of the spring's surface, the hotbar holds the kit, a dig of stone succeeds with no credit, a place of dirt succeeds with an empty inventory, nothing is saved (the saves directory stays empty).
- `./update-and-run.sh` in a clean checkout builds and launches (the user, on the couch).
