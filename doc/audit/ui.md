# Audit: the ui cluster

The ui cluster (work item 0143) is the immediate mode toolkit, every screen, the HUD, the touch overlay and the input layer: 45 files, 16604 lines, the largest cluster by references out (1927). Its debt is that the screens are the game's second simulation front end:

- The toolkit is headless and clean at its core (`ui_core.odin` and `ui_widgets.odin` make no raylib call; `ui_draw.odin` and `ui_font.odin` are the only drawing files), but game rules sit inside it: the `Screen` enum's traits as switches, the slot drag in `ui_begin`, Mission Control's timer, the game's `Touch_Button` and `Glyph_Button` values.
- 593 of the 1052 ui -> content references are the string table (`text` alone 574); the content logic in screens is small and mostly already pure (`ui_recipe_browser.odin`, `ui_technology_browser.odin`).
- The screens and the HUD write the simulation during the UI pass through 22 procedures and 9 direct field writes (section 3), beside the one queued path the game already has (`Developer_Request`).
- 148 of the 546 references into the cluster are graph noise: the layout procedure `column` (`ui_core.odin:1130`) shares its name with locals in the world, generation and render files.
- The machine panel is one kind switch written six times (`machine_area_width`, `machine_area_height`, `machine_slot_region`, `entity_status_text`, `open_machine_slot_filters`, `machine_slot_filters`), each a place where a new machine kind is added.

## 1. What the cluster is

Rule: the toolkit turns an input frame into a draw list; the screens decide what the widgets mean.

- Responsibilities: raw device reading and the action layer (`Input_Frame`), bindings, the UI's input view (`make_ui_input`), focus, pointer, drag and scroll, the widgets, the screen stack and every screen, the HUD, the touch overlay (a virtual gamepad plus its layout files and editor), text entry with the game's and the system keyboard, haptics, theme and fonts.
- Entry procedures, in frame order: `read_input_frame` (`loop.odin:349`, which calls `read_touch_overlay_frame` and one backend), `ui_begin` (`ui_core.odin:780`), `draw_hud` (`hud.odin:371`), `run_screens` (`ui_screens.odin:179`), `draw_touch_overlay` (`touch_overlay.odin:2033`), `ui_end` (`ui_core.odin:1058`, runs `execute_draw_list`); the loop wraps them in `run_ui_frame` and drains `play_ui_sounds` and `sync_system_keyboard` after.

| File | Lines | Commits | Purpose |
|---|---|---|---|
| `ui_core.odin` | 1220 | 33 | `Ui_State`, `Ui_Input`, `Draw_Command`, `Screen` and its stack, ids, focus search, pointer press, slot drag, toasts, layout cuts |
| `ui_widgets.odin` | 1380 | 23 | every widget, theme colour variables, glyph bar, touch row, tooltips, radial |
| `ui_draw.odin` | 141 | 10 | the draw list to raylib; icon atlases, image cache |
| `ui_font.odin` | 397 | 4 | TrueType families, `Font_Cache`, measuring and rasterising |
| `ui_theme.odin` | 469 | 5 | `Ui_Theme` loader, palettes, `Ui_Icon` names |
| `ui_format.odin` | 60 | 3 | one formatter per unit |
| `ui_input.odin` | 148 | 13 | `make_ui_input`, device detection, navigation direction |
| `text_input.odin` | 228 | 4 | `Text_Field`, `Keyboard_State`, the key grid's logic |
| `ui_keyboard.odin` | 182 | 3 | the text field widget and the game's keyboard |
| `ui_screens.odin` | 678 | 50 | `Screen_Context`, `handle_screen_keys`, `run_screens`, pause menu, settings |
| `ui_inventory.odin` | 343 | 14 | inventory screen, tab strip, `finish_slot_drag`, held stack drawing |
| `ui_machine.odin` | 743 | 32 | machine panel frame, furnace, inserter, drill, splitter sections, HUD target lines |
| machine panel sections: `ui_crafting_machines.odin`, `ui_fluid.odin`, `ui_power.odin`, `ui_launch_pad.odin`, `ui_prospecting.odin`, `ui_contracts.odin` | 979 | 29 (summed) | assembler and lab, fluid, power (and the power overview), launch pad (and shipments), core sample and magnetometer, venture tabs |
| `ui_recipes.odin` | 646 | 13 | recipe browser screen, `Scroll_List`, letter wheel, crafting input |
| `ui_recipe_browser.odin` | 177 | 5 | pure filtering and detail of the recipe browser |
| `ui_technologies.odin` | 237 | 7 | technology screen |
| `ui_technology_browser.odin` | 72 | 5 | pure filtering of the technology screen |
| `ui_statistics.odin` | 234 | 5 | statistics screen |
| `ui_map.odin` | 622 | 7 | `Map_View`, painting, legend |
| `ui_journal.odin` | 452 | 12 | journal, HUD objective, `wrap_text`, `format_game_time` |
| `ui_mission_control.odin` | 359 | 3 | Mission Control panel and discovery card state and drawing |
| `ui_title.odin` | 416 | 9 | `Title_State`, title, load, delete confirmation |
| `ui_world_setup.odin` | 114 | 3 | New world values, `world_settings_from_file` |
| `ui_developer.odin` | 191 | 11 | Developer screen |
| `ui_data_browser.odin` | 482 | 3 | Data files screen |
| `ui_texture_editor.odin` | 374 | 3 | Textures screen, `Texture_Editor` |
| `ui_touch_layout_editor.odin` | 506 | 5 | touch layout editor |
| `hud.odin` | 435 | 26 | crosshair, hotbar, craft queue, radial, HUD buttons, glyph hints |
| `biome_banner.odin` | 85 | 1 | biome banner state machine and draw |
| `touch_overlay.odin` | 2058 | 11 | layout files and user layouts (lines 380 to 980), gestures, gamepad merge, frame adapters, drawing |
| `input_actions.odin` | 561 | 31 | `Action`, `Raw_Input`, `Input_Frame`, `Tick_Input_Accumulator`, gyro calibration |
| `input_raylib.odin` | 352 | 18 | raylib backend, keyboard and mouse for both backends |
| `input_sdl3.odin` | 366 | 14 | SDL3 backend, Steam Controller, haptics |
| `input_sdl3_android.odin` | 23 | 2 | SDL stubs for Android |
| `bindings.odin` | 492 | 3 | bindings file, `Input_Bindings` per backend |
| `system_keyboard_linux.odin`, `system_keyboard_android.odin`, `system_keyboard_windows.odin` | 95 | 4 | show and hide the platform keyboard |
| `haptics_android.odin`, `haptics_desktop.odin` | 287 | 3 | vibrator through JNI; the JNI helpers |

Verdicts on edge assigned files:

- `biome_banner.odin` (graph: ui) is ui, a HUD notice like the discovery card. Its only world edge is `draw_biome_banner` calling `sample_column` on the generator every frame; given the biome index by the frame, it loses that edge and `Screen_Context` keeps `generator` for the map alone.
- `quick_transfer.odin` (graph: simulation) is split: every caller is a ui file, and it holds UI state (`Quick_Move_State`, `advance_quick_move`, `quick_move_target` over `Slot_Grid_Result` and `Machine_Slot_Result`, `transfer_button_rows` drawing buttons) beside the transfer verbs (`apply_quick_move`, `apply_grid_transfer`, `apply_transfer_button`, `take_inserter_hand`). The first half is ui, the second the simulation's commands.

## 2. State

Rule: `Ui_State` lives for the process; screen state lives where its lifetime is (a world, a process, a frame).

`Ui_State` (`ui_core.odin:385`, 57 fields) by owner:

| Group | Fields | Count |
|---|---|---|
| toolkit set-up | theme, fonts, measure_text, accessibility | 4 |
| this frame (ui_begin, widgets, ui_resolve) | input, frame_seconds, pixels_per_unit, screen_units, frame_count, focus_pulse_seconds, focus_pulse, navigation_step, confirm, click, pointer_held, pointer_released, pointer_drag, id_stack, id_depth, current_panel, focused_tooltip, preferred_focus, widgets, panels, draw_list, sound_events, back_tapped | 23 |
| focus and navigation | focus, requested_focus, focus_rest_id, focus_rest_seconds, repeat, tooltip_open, focus_scrolled_away | 7 |
| pointer and touch | pointer, pointer_source, pointer_moved, pointer_speed, pointer_press, hovered, dragging, active_device | 8 |
| widget memory by id | scroll_offsets, selections, knob_positions, slider_drag_value | 4 |
| screens | screens | 1 |
| keyboard | keyboard, system_keyboard | 2 |
| game: HUD and notices | radial (the hotbar wheel), toasts, toast_top_offset, mission_control | 4 |
| game: slot screens | slot_drag, distribute, quick_move, active_slot | 4 |

- Writers outside the toolkit: the loop (screens, keyboard, tooltip_open, system_keyboard, mission_control, fonts, measure_text; `loop.odin:1008` to `loop.odin:1117`), `hud.odin` (radial, toast_top_offset), `sound_events.odin` (clears sound_events), `hot_reload.odin` and `ui_theme.odin` (theme), the screens (screens, keyboard, requested_focus, active_slot, distribute, quick_move, slot_drag).
- Screens rewrite the frame's input to consume edges: `ui_inventory.odin:86`, `ui_inventory.odin:253`, `ui_inventory.odin:256`, `ui_machine.odin:492`, `ui_data_browser.odin:102`; `ui_begin`'s slot drag synthesises Confirm, `Menu_Secondary` and Back the same way (`step_slot_drag`, `end_slot_drag`).
- The theme is held twice: `Ui_State.theme` and eight package variables (`UI_PANEL_COLOR`, `UI_TEXT_COLOR` and the rest, `ui_widgets.odin:48` to `ui_widgets.odin:55`) that `apply_ui_theme` assigns and screens read 168 times. It is the cluster's only mutable package state.

`Screen_Context` (`ui_screens.odin:19`, 54 fields), in the loop audit's groups, with the files that read each group:

| Group | Fields | Read by |
|---|---|---|
| process (8) | settings, monitor_size, platform, font_families, bindings, quit_requested, save_requested, title | `ui_screens.odin`, `ui_title.odin`; settings also developer and data browser |
| content (14) | items, blocks, item_sort_ranks, machines, fluids, veins, tick_rate, recipes, technologies, quests, contracts, notes, recipe_names, recipe_order | every world screen and the HUD |
| simulation (10) | player, player_index, world, unlocks, quest_state, tick, generator, cheat_speed, developer_requests, landing_pad | world in 14 files, player in 8 |
| session views (4) | browser, technology_browser, statistics_view, map_view | one screen each, plus `run_screens` resetting two |
| developer (9) | developer_mode, diagnostics_page, show_world_overlay, developer_chapter_count, screenshot_requested, reload_requested, data_changed, texture_editor, data_browser | `ui_developer.odin` (8 of 9), the two editors |
| HUD and touch (9) | biome_banner, particle_memory, touch_aims, mining_ring_centre, touch_hud_buttons, discovery_card_clearance, touch_layouts, touch_layout_editor, default_touch_layout | `hud.odin` (4), `ui_map.odin`, settings and the layout editor |

- 9 of the 54 fields are read in exactly one place; `draw_hud` takes the whole struct for 4 HUD fields plus world reads.
- `statistics_simulation_content` (`ui_statistics.odin:130`) rebuilds a `Simulation_Content` from 5 of its fields for the machine panel's transfers; blocks, fluids, quests, contracts and the generator stay zero. It holds because `entity_accepts` and its callees read only items, machines and recipes today.

Where each screen keeps its state:

- `Ui_State`: keyboard (`Keyboard_State`), Mission Control (`Mission_Control_State`), the slot screens' four groups, the hotbar radial; tab and list positions of every screen as `selections` and `scroll_offsets` keyed by widget id.
- `Session`: `Recipe_Browser`, `Technology_Browser`, `Statistics_View`, `Map_View` (the loop audit's refactor 8 moves them out).
- `Frame_State`: `Title_State` with `World_Setup`, `Biome_Banner`, `Texture_Editor`, `Data_Browser`, `Touch_Layouts`, `Touch_Layout_Editor`, `Touch_Overlay_State`.
- `Player` (simulation, saved): the cursor stack `held` (`Held_Stack`), `open_machine`, `selected_hotbar_slot`, the crafting queue. Keeping the cursor in the simulation keeps items from vanishing; it is also why the slot screens write the simulation every frame.
- The recipe browser keeps a second `Radial_State` (its letter wheel) in `Recipe_Browser`.

## 3. Coupling

Rule: a screen reading the world to show it is essential; a screen writing the world outside the tick is the reach through a boundary would have to queue.

ui -> content (1052) by what is referenced:

| Kind | References | Examples |
|---|---|---|
| strings | 593 | `text` 574, `replace_message_mark` 15, `format_message_text` 4 |
| registries and their lookups | 265 | `Item_Registry` 46, `item_name` 19, `NO_RECIPE` 19, recipes, technologies, quests, contracts, unlocks, venture |
| settings and configuration | 83 | `Settings` 27, `Configuration_Provenance`, ranges, local zone |
| developer tools | 66 | `Data_Browser` 15, `Developer_Request` 12, data load and reload |
| platform | 23 | JNI indices and `Android_Native_Activity` from haptics and the Android keyboard |
| logging | 22 | `log_printf` |

- Content logic in screens: view models, not rules. The recipe browser's filtering and detail (`filter_recipes`, `recipe_detail`, `crafts_covered`) and the technology filter are pure and tested; the journal orders quests (`journal_quest_order`) and names objectives; `vein_status_text` applies the discovery rule (`vein_type_is_discovered`) for the HUD.

ui -> simulation (631): about 560 are types, constants and read accessors (`Item_Stack` 37, `Inventory` 34, `pool_get` 32, `Machine` 29, the per kind fractions and state texts). The writes during the UI pass:

- Slot screens: `apply_slot_primary`, `apply_slot_split`, `apply_slot_context`, `apply_machine_slot_primary`, `finish_distribute`, `sort_slots`, `return_held_stack`, `apply_inventory_quick_move`, `apply_quick_move`, `take_inserter_hand`, `apply_transfer_button`, `apply_grid_transfer`, `drop_player_stack`; direct writes to `player.held` (9 lines), `player.open_machine` (`close_slot_screens`), `inserter.filter` and `inserter.held` (`ui_machine.odin:529`), `splitter.filter` and its priorities and side (`ui_machine.odin:334` to `ui_machine.odin:345`, `ui_machine.odin:534`).
- Other screens: `toggle_power_switch` (`power_panel_region`), `start_assembly`, `request_launch`, `record_launch_refusal` (`launch_pad_slot_region`), `order_from_catalogue` (`launch_pad_catalogue_tab`), `queue_crafts` and `cancel_last_craft` (`apply_recipe_craft_input`), `change_assembler_recipe` (`choose_assembler_recipe`), `queue_research` (`queue_focused_research`).
- HUD: `hotbar_radial` sets `player.selected_hotbar_slot` (`hud.odin:273`), while the tick's writer reads actions (`cycle_hotbar_slot`, `player.odin:537`) and the touch overlay's hotbar goes through the input frame (`apply_touch_overlay_hotbar`).
- The queued exception: the Developer screen appends `Developer_Request` entries that `serve_developer_requests` applies inside the tick.

Other edges out: ui -> world 145 (`World` 21, `Block_Registry` 16, veins, the map's `collect_explored_surfaces` and `sample_column`, the title's `list_saves` and `delete_save`), ui -> presentation 83 (the texture editor's procedural textures 30, `render_size`, display modes), ui -> loop 16 (`touch_overlay.odin` taking `Frame_State`, covered by the loop audit).

Edges in (546; loop -> ui 212 is in the loop audit):

- world -> ui 122: 121 are `column` name collisions; the one real edge is `save_world.odin` and `session.odin` calling `world_settings_from_file` (`ui_world_setup.odin:85`), a world rule in a UI file.
- content -> ui 114: 42 from `export_access_android.odin` to the JNI helpers defined in `haptics_android.odin`; 11 `Slider_Range` (settings ranges typed by a widget type); 20 from the hot reload and data watch naming the font, theme, bindings and overlay loaders (essential while the loaders live here); 6 `ui_toast`; 6 `Input_Frame`; 5 `column`.
- simulation -> ui 70: 36 are the tick's input types (`Input_Frame`, `Action_Set`, `Raw_Input`), essential; 21 from `diagnostics.odin` (input labels, `draw_monospace_text`); 11 `column`; 11 from `quick_transfer.odin` (its UI half).
- presentation -> ui 28: `Ui_Color` 7, palettes for the bottleneck markers, `Ui_Sound_Event`, 11 `column`.
- Cycles: ui is in a mutual pair with every cluster. Without the `column` noise, ui <-> world rests on `world_settings_from_file` alone, and ui <-> simulation on `quick_transfer.odin` plus the input types.

## 4. Abstraction gaps

- Four copies of one row helper: settings_row, choice_row, developer_row, title_row (cut a row, cut a gap; one `cut_row` since 0148).
- Toolkit pieces live in screen files: `Scroll_List` and `scroll_list_begin` in `ui_recipes.odin`; `wrap_text`, `take_line`, `draw_wrapped`, `format_game_time` in `ui_journal.odin`; `detail_line` in `ui_power.odin`; `panel_height` in `ui_screens.odin`; `target_status_lines` (HUD) in `ui_machine.odin`.
- List plus detail is written per screen: `focus_recipe_row` and `settle_recipe_focus`, `focus_technology_row` and `settle_technology_focus`, `focus_statistics_row` and `settle_statistics_focus` are the same two procedures over a different browser struct.
- Slot screens: `inventory_screen` and `machine_screen` repeat one sequence (quick move input, active slot, slot input, touch row button, transfer, `finish_slot_drag`, `draw_held_stack`, glyph bar), with twin quick move adapters (`apply_inventory_quick_move_input`, `apply_quick_move_input`).
- The machine panel's kind switches (summary) compute the height separately from the drawing (`machine_area_height`, `DRILL_TEXT_ROWS`, `fluid_area_size`, `crafting_machine_area_height`), so a new row is two edits the audit test has to catch. Two enums dispatch it: `Machine_Kind` for size, the entity handle's kind for drawing.
- Screen traits as switches over the game's `Screen` in the toolkit: `screen_pauses_simulation`, `screen_closes_on_outside_tap`, the Back sound except on the title (`ui_core.odin:831`), plus `handle_screen_keys`' seven open and seven close cases and `run_screens`' dispatch. A screen is five edits.
- Glyphs were a nested switch keyed by `Glyph_Button`, taking no bindings: a rebinding in the configuration kept the default glyphs. Since 0151 `glyph` shows the bound control.
- `Ui_Input` (42 fields) copies seven screen toggles out of the action set (`open_inventory` to `open_map`) as booleans; a new screen key is a field, a line in `make_ui_input` and a case in `handle_screen_keys`.
- Bundles: `Screen_Context` passed whole to every screen and the HUD; `target_status_lines` takes 9 parameters; `drill_vein_lines`, `vein_status_text` and `bore_drill_ghost_line` each take world, veins, blocks, items and obtained.
- The three backends differ in shape: `read_sdl3_input_frame` takes state, the previous frame, seconds, settings, bindings and overlay; `read_raylib_input_frame` the previous pressed set, bindings and overlay; the Android stub returns the previous frame. Both real ones repeat the same dozen lines turning raw input into `Input_Frame` (move, look, look delta, pressed, just pressed), and `read_input_frame` picks them with a switch.
- `Input_Frame` carries `raw` (`input_actions.odin:214`), the whole device state including `Raw_Gamepad.name` (a C string), into the tick accumulator; the simulation never reads it (only `ui_input.odin`, `diagnostics.odin` and `input_sdl3.odin` do).
- File work in the UI pass: `delete_title_save` removes a save directory and rebuilds `Title_State.saves` inside the frame, unlike the data browser's requests the loop serves. It is safe today because the only save text drawn that frame is copied by `format_message_text` into the temp allocator.

## 5. Refactors, ranked by gain per risk

1. Rename `column` and move three misplaced definitions. Rename the layout procedure (a longer name such as column_rectangle, 39 call sites in 8 files); move `world_settings_from_file` to `save_world.odin` or the world settings file; move the JNI helpers (`jni_method`, `jni_find_class`, `Jni_Calls` and the rest) from `haptics_android.odin` to `platform_android.odin`. Files: the ui files calling `column`, `ui_world_setup.odin`, `haptics_android.odin`, `platform_android.odin`. Guards: `./build.sh check`, `./build.sh check-android`, `ui_world_setup_test.odin`. Gain: references into ui from 546 to about 355; world -> ui from 122 to 0. Risk: none. Prerequisite: yes, the graph then shows the real seams.
2. Move the toolkit out of the screen files and merge the row helpers: the four row helpers into one, `Scroll_List` and its procedures, `wrap_text`, `take_line`, `draw_wrapped`, `detail_line`, `panel_height` into `ui_widgets.odin`, `format_game_time` into `ui_format.odin`, `target_status_lines` and its helpers into `hud.odin`. Guards: `test_every_screen_stays_inside_the_screen`, `test_a_drag_scrolls_the_recipe_list`. Gain: 3 procedures and about 15 lines gone; the toolkit files name no screen. Risk: none (same package). Prerequisite: yes, for a toolkit package.
3. A screen table: one `[Screen]` table row per screen holding its procedure, whether it pauses, whether an outside tap closes it and its toggle action; `run_screens`, `screen_pauses_simulation`, `screen_closes_on_outside_tap` and the open and close halves of `handle_screen_keys` read it. The keyboard exception (Open_Inventory closing the strip unless it is the context action) stays a line. Files: `ui_core.odin`, `ui_screens.odin`. Guards: `test_screen_stack_and_back`, `test_open_inventory_closes_the_strip`, `test_a_tap_outside_closes_every_screen_with_a_panel`, `test_every_screen_has_a_back_button_on_touch`, the audit's walk of every screen. Gain: a screen is one row instead of five edits; the toolkit stops switching over game screens. Risk: low. Prerequisite: yes.
4. One theme copy: read colours through `theme_color` or a theme value everywhere and delete the eight package variables. Files: every screen (168 references), `ui_widgets.odin`, `ui_theme.odin`, the comment in `main_android.odin`. Guards: `ui_theme_test.odin` (15 tests), the audit. Gain: no mutable package state in the cluster, which a toolkit compiled into a plugin or two `Ui_State` values need. Risk: low, mechanical.
5. One raw to frame procedure and a tick input without `raw`. Each backend returns `Raw_Input` (the SDL one with its gyro calibration applied); one shared procedure builds `Input_Frame` from the previous and current raw input, bindings and overlay; the UI keeps its own previous and current raw input, and the tick accumulator takes the frame without raw. Files: `input_raylib.odin`, `input_sdl3.odin`, `input_sdl3_android.odin`, `input_actions.odin`, `ui_input.odin`, `loop.odin`, `diagnostics.odin`. Guards: `input_actions_test.odin`, `test_tick_input_sums_look_delta_of_frames_between_ticks`, `test_a_blocked_frame_reaches_the_next_tick`, `touch_overlay_test.odin`; the backends need a couch and a phone playtest. Gain: about 20 lines, one place for the action assembly, a tick input with no host pointer in it. Risk: low. Prerequisite: yes, it is the tick's parameter across a boundary.
6. One slot screen frame. A procedure running the sequence of section 4 over the player's grids and an optional machine side (slots, filters, kind); `inventory_screen` and `machine_screen` keep their layout and extras. Move the UI half of `quick_transfer.odin` beside it. Files: `ui_inventory.odin`, `ui_machine.odin`, `quick_transfer.odin`. Guards: `ui_inventory_test.odin` (25 tests), `quick_transfer_test.odin`, `test_inventory_screen_quick_move_and_drop`, `test_the_touch_row_clears_a_filter`, `test_sort_touches_only_the_active_grid`, audit cases "inventory touch row" and "machine ... touch row". Gain: about 60 lines; the input order (quick move before slot input, distribute before buttons) in one place. Risk: medium, order sensitive but well tested.
7. Split `Screen_Context` by consumer: a HUD context for `draw_hud` (the 4 touch derivations, biome index, the player and the world reads it makes), the content group as one embedded struct (after the loop audit's refactor 2 it is `Simulation_Content` plus names), the developer group as one pointer. Files: `ui_screens.odin`, `loop.odin`, `hud.odin`, `biome_banner.odin`, `ui_developer.odin`, `ui_audit_test.odin`. Guards: `./build.sh test`, the audit. Gain: 54 top level fields to about 12; `audit_screen_context` shrinks with it. Risk: low, large diff; after the loop audit's refactors 7 and 8.
8. Queue the screens' simulation writes as player commands, served at the start of the next tick as `serve_developer_requests` serves developer requests: research, crafting and cancelling, recipe choice, power switch, assembly and launch, catalogue orders, splitter and inserter settings; the hotbar radial emits a hotbar slot action as the touch overlay does. The slot transfers stay immediate for now, since the drag shows their result the same frame. Refusal toasts use the pure refusal checks the screens already call (`assembly_refusal`, `launch_refusal`) before queuing. Files: the eight screen files of section 3, `hud.odin`, `developer.odin`, the simulation's tick. Guards: `test_a_tap_on_a_technology_selects_it_and_research_starts_it`, `test_a_tap_on_a_recipe_selects_it_and_the_row_crafts`, `test_radial_selects_hotbar_slot` (rewritten to read the action), `launch_pad_test.odin`, `power_test.odin`, `lab_test.odin`. Gain: 9 of the 22 mutating procedures and 6 of the 9 field writes leave the UI pass; replay and a plugin boundary see them as tick input. Risk: medium, one frame of latency and tests that must run a tick. Prerequisite: yes, for the plugin cut.
9. Machine panel sections: an entity's panel as a list of sections (burner row, slot rows, progress bar, fluid rows, power line, state line, output rate) derived from what the entity carries, measured and drawn by the same code; kind specific sections for the splitter, inserter filter and hand, assembler recipe, lab research, launch pad tabs, core sample and drill vein lines. Files: `ui_machine.odin` and the six section files. Guards: every "machine ... tab N" audit case, `test_the_machine_row_keeps_its_places_at_the_deck_size`, `test_a_drag_moves_a_stack_into_a_chest`. Gain: six kind switches to one table, height and drawing cannot drift, about 150 lines. Risk: medium to high, layout at every audit size. Prerequisite: no, but it is the shape an entity component query would feed (section 7).

## 6. Engine or game

Rule: what knows no item, machine or screen is engine.

- Engine: `ui_draw.odin`, `ui_font.odin`, the theme loader, `text_input.odin`, `ui_keyboard.odin`, `system_keyboard_linux.odin` and its siblings, `haptics_android.odin`, the raw input types, `Tick_Input_Accumulator`, gyro calibration, `input_raylib.odin`, `input_sdl3.odin`, the bindings parser, and the toolkit's core: ids, focus search, pointer press, scrolling, the generic widgets, the draw list.
- Game: every screen, the `Action` vocabulary, `Glyph_Button`, `Touch_Button`'s values, `Ui_Input`'s screen toggles, `Screen` and its traits, `Slot_Drag` and the slot groups, Mission Control, the item slot widgets (they draw `Item_Stack` through `draw_item_icon`).
- Both: the HUD (layout helpers engine, what it shows game); the touch overlay (gesture machine, layout files and gamepad merge engine; the hotbar, HUD buttons, jump zone and the tap's Interact or Place choice through `entity_takes_interact` game).

What the screens need from an engine side toolkit across a plugin boundary:

- Immediate mode per widget call across wasm: every `ui_interact` reads the focus and pointer and appends a widget and draw commands, and every fitted or wrapped text calls `measure_text`; hundreds of crossings per frame on a list screen (not measured; the audit's draw list length per case gives the number).
- A retained description per frame, which the code already has: the toolkit makes no raylib call, so it can be compiled into the game side, taking `Ui_Input` in and handing back the `Draw_Command` list and `sound_events` once per frame. The one callback is `Measure_Text_Proc` (replaceable by shipping glyph advance tables, as `approximate_text_width` shows the toolkit works without fonts). `Draw_Command.text` and `Draw_Command.pixels` point into guest memory, read through bounds checked views as heimdall does.
- The screens' query surface, by kind of world read today:
  - player: inventory, `held`, selected slot, crafting queue, target hit, mining state, magnetometer reading, position and movement flags, tool tier, open machine;
  - entity by handle: common data, slots (`entity_slots`), and the per kind structs of 12 kinds;
  - power: networks, participants, an entity's network (`entity_network`), brownout;
  - fluids: buffers of an entity, `segment_is_above_head_line`;
  - world records: statistics and rates, research, shipments, contracts and venture credit, veins (`registered_vein`, `vein_at_column`, `vein_is_assayed`), core samples, seismic outlines, magnetometer readings, explored surfaces, the targeted block, world settings, entity cells for map dots;
  - generator: `sample_column` for biomes (map, banner);
  - simulation: unlocks, quest state, tick, cheat speed, pending developer requests.
- Writes across the boundary: the command list of refactor 8 plus the slot transfers, each a call applied at the next tick.

## 7. Entity component lens

Rule: a panel section per component, a panel per kind only where the kind has its own controls.

What the panels read per entity, and how many kinds carry each today:

- Slots: every panel kind; already reached through one accessor (`entity_slots`) with one case per slotted kind.
- Burner: fuel slot and a burn fraction, written five times (`furnace_burn_fraction`, `inserter_burn_fraction`, `drill_burn_fraction`, `assembler_burn_fraction`, `boiler_burn_fraction`).
- Progress: seven procedures (`furnace_progress_fraction`, `drill_progress_fraction`, `assembler_progress_fraction`, `lab_progress_fraction`, `inserter_cycle_fraction`, `launch_pad_progress`, `core_sample_fraction`).
- State: a key table or text per kind (`furnace_state_keys`, `assembler_state_keys`, `lab_state_keys`, `fluid_machine_state_keys`, `inserter_state_text`, `drill_state_text`, `launch_pad_state_text`).
- Fluid ports: `buffers` and `closed` arrays on drills, assemblers, fluid machines and launch pads, drawn by one `fluid_buffer_rows`; pipes hold one buffer.
- Power: by handle through `power_status_line`, already a query, not a field.
- Output rate: `Machine_Output_Rate` on furnaces, drills and assemblers.

Verdict:

- A component query (does this entity have a burner, progress, fluid ports, an output rate) would replace the per kind section order in `furnace_slot_region`, `drill_slot_region`, `assembler_slot_region`, `fluid_machine_slot_region` and `lab_slot_region`, and the size switches with them. Refactor 9 gets the same shape without an ECS by asking per kind accessors.
- Inherent per kind: the splitter's priorities and side, the inserter's filter and hand, the assembler's recipe choice, the lab's research, the launch pad's three tabs, the core sample's bands, the drill's vein lines. These stay kind panels under any storage.
- The HUD's `entity_status_text` is the same switch in one line per kind; it becomes name plus the state component.

## 8. Tests

Rule: the toolkit and the pointer are tested well; the backends and the draw layer are not.

- Covered: `test_every_screen_stays_inside_the_screen` runs about 30 named cases (title, new world, both keyboards, load, confirm delete, the HUD variants, pause, five settings tabs, developer, textures, data files, the layout editor, inventory, every machine with a panel and each launch pad tab, recipes, recipe selection, technologies, every journal tab and note, three statistics tabs, power, map, the touch rows) at every audit size; focus search and widgets (`ui_core_test.odin`, 29); the pointer, taps, drags, scrolling and the touch rows (`ui_pointer_test.odin`, 23); slot drag and drop, quick move, the active grid (`ui_inventory_test.odin`, 25); transfers (`quick_transfer_test.odin`, 20); the touch overlay's gestures and loader (`touch_overlay_test.odin`, 68); text entry, fonts, theme, Mission Control, the editors and the data browser.
- Uncovered: `read_sdl3_input_frame`, `read_raylib_input_frame` and `keyboard_mouse_actions` (need devices); `execute_draw_list` and the font rasterisation (need a window); `apply_sdl3_haptics` and the vibrator; showing and hiding the system keyboard (only the Steam link text is tested); the distribute gesture through `machine_screen` (only `distribute_held_stack` and `gesture_visit` are tested); `delete_title_save` in the frame; `draw_biome_banner`'s generator read.
- Pinning implementation: `ui_pointer_test.odin` and `ui_touch_layout_editor_test.odin` rebuild widget ids with `ui_hash` over panel labels and read `scroll_offsets` by that id (about 30 sites), so renaming a panel label breaks them; `test_radial_selects_hotbar_slot` asserts the direct write to `player.selected_hotbar_slot` that refactor 8 removes; `audit_screen_context` copies `make_screen_context` (loop audit).

## Claims to spot check

1. `hotbar_radial` writes `player.selected_hotbar_slot` during the UI pass (`hud.odin:273`), while the tick changes it only from actions (`player.odin:537`) and the touch overlay's hotbar goes through `apply_touch_overlay_hotbar`.
2. 121 of the 122 world -> ui references are the identifier `column` (`ui_core.odin:1130`) matching locals in world and generation files; the one real edge is `world_settings_from_file` (`ui_world_setup.odin:85`), called from `save_world.odin:600` and `session.odin:89` (probe over `tools/code_graph.py`'s parser).
3. The glyph lookups (`ui_widgets.odin`) took no bindings, so a configured rebinding kept showing the default glyphs. Fixed by 0151 (`glyph`).
4. `apply_ui_theme` (`ui_theme.odin:287`) writes `Ui_State.theme` and eight package colour variables (`ui_widgets.odin:48` to `ui_widgets.odin:55`); the variables are read 168 times.
5. `Input_Frame.raw` (`input_actions.odin:214`) goes into the tick input with the whole device state, while only `ui_input.odin`, `diagnostics.odin` and `input_sdl3.odin` read it.
