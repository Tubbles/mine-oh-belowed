# 0302: Tech demos on the title, the shim retired

Status: verified (2026-11-06)

Milestone: the water tech demo (0291). The user (2026-11-06): the tech demos move into the real game as a main menu option called "tech demos", instead of being reached through their own `update-and-run.sh` shim.

## Goal

The play build (`tools/install_play_build.sh`, the "Mine oh Belowed" Steam shortcut) is the one way into the tech demos: its title has a "Tech demos" button that lists the demos, today the water one. `update-and-run.sh` and the tech demo's own Steam shortcut are gone.

## Controls

Control design (main agent, 2026-11-06), no new binding, no world control touched:

- Title: the "Water tech demo" button becomes "Tech demos", in the same place (after New world, before Load).
- A new title screen `Tech_Demos`: a heading "Tech demos", one button per demo (today "Water", which pushes the existing `Tech_Demo` screen), then Back. Navigated as every title screen: D-pad focus, Confirm (A) selects, Back (B) pops. Back on the water screen returns to this list.
- `--tech-demo` alone opens the title with `Tech_Demos` and the water screen pushed, so Back walks the same way as from the title. `--tech-demo=<model>,<radius>,<start>` is unchanged.

## Change

- `ui_title.odin` (the button and its string), a `Tech_Demos` screen beside `ui_tech_demo.odin`, the screen enum and its dispatch, the bare flag's push in `loop.odin`, the strings.
- Remove `update-and-run.sh` and `add_steam_shortcut.py --tech-demo` (its app name, its target, its flag).
- Docs: `doc/build.md` (the command line row, the Steam shortcut, The water tech demo section), `doc/ui.md` (Title, the new screen, the screens table), `doc/code_map.md`.

## Verify

- The checks and the suite; the UI audit draws `Tech_Demos` and walks its focus at the smallest audit size, and the water screen's audit case starts from it.
- A test: the title's Tech demos button pushes `Tech_Demos`, its Water button pushes `Tech_Demo`.
- A headless screenshot of the title and of the Tech demos screen.

## Specification (design, 2026-11-06)

Designed against `main` at 31a2768. The list screen goes into `ui_tech_demo.odin`: it is one more procedure of the same concern, and a file of its own would hold one procedure behind a code map line of its own.

### Code

- `src/ui_core.odin`: `Screen` gains `Tech_Demos` right before `Tech_Demo`, comment `// The tech demos' list (ui_tech_demo.odin, 0302).` (`Screen` is not saved, so the value shift is harmless.) `screen_pauses_simulation` names it in the pausing case beside `.Tech_Demo`. `screen_closes_on_outside_tap` (a `#partial switch`) stays as it is, so a tap off the panel closes the list as it closes the water screen.
- `src/ui_screens.odin`, `run_screens`: `case .Tech_Demos: tech_demos_screen(state)` before `case .Tech_Demo`. These two switches are the only ones over `Screen`.
- `src/ui_tech_demo.odin`:
  - Header comment: the file is the tech demos' list (0302) and the water tech demo's menu (0291).
  - `TECH_DEMOS_ROW_COUNT :: 3` (heading, Water, Back).
  - `tech_demos_screen :: proc(state: ^Ui_State)`: `fitted_panel(ui_panel_area(state), TITLE_PANEL_WIDTH, panel_height(TECH_DEMOS_ROW_COUNT, -UI_GAP))`, `ui_panel_begin(state, "tech_demos", panel)`, then the heading `tech_demos_title` at `UI_HEADING_TEXT_SIZE`, centred. Then a full row `ui_button` `tech_demos_water` that pushes `.Tech_Demo`, and a full row `ui_button` `new_world_back` that calls `pop_screen`. `ui_panel_end`, and the glyph bar as `tech_demo_screen`'s (Confirm `hint_select`, Back `hint_back`, `ui_glyph_bar_or_back_row`). No `ui_backdrop`, as on the water screen. It takes no `Screen_Context` because it reads none.
  - `push_tech_demo_menu :: proc(screens: ^Screen_Stack)`: pushes `.Tech_Demos`, then `.Tech_Demo`. It is the bare `--tech-demo`'s screens over the title, so Back walks the way it does from the title. Called from `run_game`.
- `src/ui_title.odin`, `title_screen`: the button's key becomes `title_tech_demos` and it pushes `.Tech_Demos`, in the same place. `button_count` is unchanged. The header comment names the tech demos' list and the water menu in `ui_tech_demo.odin`.
- `src/loop.odin`, `run_game` (line 1901): `push_screen(&primary_ui(state).screens, .Tech_Demo)` becomes `push_tech_demo_menu(&primary_ui(state).screens)`.
- `src/configuration.odin`, the `tech_demo_menu` comment: "--tech-demo alone (0291): the title opens with the Tech demos list and the Tech demo screen pushed (`push_tech_demo_menu`, 0302)."
- `src/main.odin`: in the `tech_demo` usage string, "alone, the title with the Tech demo screen open" becomes "alone, the title with the Tech demos list and the water screen open". The comment above `tech_demo_opens_menu` gets the same words.

### Strings (`data/strings/en.sjson`)

- `title_tech_demo = "Water tech demo"` is replaced in place by `title_tech_demos = "Tech demos"`.
- At the head of the `// Tech demo screen (0291)` block, under a comment `// Tech demos list (0302)`: `tech_demos_title = "Tech demos"` and `tech_demos_water = "Water"`.
- Back reuses `new_world_back`, as the water screen does.

### Files removed

- `update-and-run.sh` (`git rm`).
- `tools/add_steam_shortcut.py` goes back to its content before 0291: `git checkout 0c631bf -- tools/add_steam_shortcut.py`. Only 0291 (`d640bf2`) touched the file since, and its changes are exactly the `--tech-demo` flag, the two `TECH_DEMO_*` constants, `build_shortcut`'s parameters and the docstring lines. Check: `python3 tools/add_steam_shortcut.py --help` lists no `--tech-demo`.

### Tests

- `src/ui_tech_demo_test.odin`:
  - Two id helpers: `title_button_id :: proc(key: string) -> Ui_Id` (`ui_hash(ui_hash(0, "title", -1), text(key), -1)`) and `tech_demos_button_id`, the same under `"tech_demos"`. The pattern is `pause_button_id`'s.
  - `test_the_title_opens_the_tech_demos_list_and_the_water_screen`: build `make_ui_audit` and a `Ui_State` with `.Title`, then run one `screen_test_frame` with `{}`. Set `requested_focus = title_button_id("title_tech_demos")` and run a gamepad frame (`{device = .Gamepad, device_seen = true}`); the focus is that id. A Confirm frame (`confirm = true, confirm_down = true` plus the gamepad fields) leaves the top `.Tech_Demos` with count 2. Then the same focus and Confirm on `tech_demos_button_id("tech_demos_water")` leaves the stack exactly `.Title, .Tech_Demos, .Tech_Demo`. A frame with `{back = true}` leaves `.Tech_Demos` on top, and a second leaves `.Title` with count 1. The focus and Confirm steps are `test_confirm_on_developer_toggles_nothing`'s.
  - `test_the_bare_tech_demo_flag_opens_the_list_under_the_water_screen`: a `Screen_Stack` holding `.Title`, then `push_tech_demo_menu`, gives count 3 with `.Title, .Tech_Demos, .Tech_Demo` in order. With `test_command_line_tech_demo` (bare flag means `tech_demo_opens_menu`), this covers the flag's path. `run_game` itself needs a window.
- `src/data_strings_test.odin`, `test_shipped_strings_cover_the_ui`: add `#load("ui_title.odin", string)` and `#load("ui_tech_demo.odin", string)` to `sources`, so the new keys are checked. Every literal key in both files is in `en.sjson` today (checked at design).
- `src/ui_audit_test.odin`:
  - `audit_every_case`: add `{name = "tech demos", screens = {.Title, .Tech_Demos}, walk_focus = true}` before "tech demo", whose screens become `{.Title, .Tech_Demos, .Tech_Demo}`.
  - `audit_touch_rows`: add `{name = "tech demos", screens = {.Title, .Tech_Demos}}`, and "tech demo"'s screens become `{.Title, .Tech_Demos, .Tech_Demo}`.
  - `audit_case` runs every `UI_AUDIT_SIZES` entry, so the smallest size is covered.

### Docs

- `doc/build.md`:
  - The Command line row of `--tech-demo`: "alone, the title with the Tech demos list and the Tech demo screen open".
  - Steam shortcut: delete the `--tech-demo` bullet.
  - The water tech demo:
    - The opening "The couch build that judges" becomes "The play build's mode that judges".
    - First bullet: "the title's "Water tech demo" button opens the Tech demo screen" becomes "the title's Tech demos button opens the list of the tech demos (0302), whose Water opens the Tech demo screen". "Back on the screen returns to the title" becomes "returns to the list".
    - Second bullet: "opens the title with the Tech demos list and the Tech demo screen pushed (`push_tech_demo_menu`)".
    - The `update-and-run.sh` and `--tech-demo` shortcut bullets are replaced by one: the way in is the play build ([Play build](#play-build)) and its "Mine oh Belowed" shortcut ([Steam shortcut](#steam-shortcut)). The launcher passes its arguments on, so LaunchOptions `--tech-demo` opens the list with the water screen, and `--tech-demo=<model>,<radius>,<start>` opens the demo world.
- `doc/ui.md`:
  - The screens table: "Tech demos" before "Tech demo" in the pausing column.
  - Other screens, Title: "Water tech demo (0291)" becomes "Tech demos (0302)".
  - A new bullet before **Tech demo**: **Tech demos** (0302, `ui_tech_demo.odin`): the list of the tech demos, one button per demo (today Water, which opens the Tech demo screen), then Back. Back on the Tech demo screen returns here. Navigated as every title screen; the audit draws it and walks its focus.
- `doc/code_map.md`, the `ui_tech_demo.odin` line: "the Tech demos list (0302) and the Tech demo screen (0291), `Tech_Demo_Setup` and its rows' steps, the tech demo request, the bare flag's screens (`push_tech_demo_menu`)". The record's counts follow `tools/code_graph.py --check`: loop may reach ui, so none are expected to move.
- No change: `doc/architecture.md`, `doc/content.md`, `doc/input.md` and `doc/developer_tools.md` name the water screen, which keeps its name, or the flag's world form. The `doc/README.md` index still names The water tech demo section. `doc/log/` is the main agent's at landing.

### Hand-back check

- A list that grows without bound, a long string: the list holds one fixed button and the labels go through `ui_button`'s fitted text. Both audit cases run at every size, the smallest included.
- A UI audit case a change makes obsolete: the "tech demo" cases still draw the water screen, now reached through the list, and the list gets cases of its own.
- Tests never touch the machine's state: the new tests use `make_ui_audit` and a bare `Screen_Stack`.
- The other lines do not apply: nothing is freed mid frame, no file is written, there is no start-up load, no number is parsed, the save layout and shared budgets are untouched.

Verify for the implementer: `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, and `python3 tools/add_steam_shortcut.py --help`. The headless screenshots of the title and of the list are the main agent's.

### Notes for the main agent

- The couch's Steam still holds the "Mine oh Belowed: water tech demo" entry, pointing at the deleted script. The tool only upserts and never removes, so the entry is removed by hand in Steam (Manage, Remove non-Steam game). The spec adds no removal code.
- `update-and-run.sh` rebuilt from `main` at every launch. The couch now sees a change only once a play build is installed, which the landing already does.
