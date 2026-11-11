# 0341: Input injected through the command socket

Status: verified (2026-11-11)

A headless session is framed through the command socket (0183), but a screen the commands do not reach (a menu, a panel, the inventory view) is still driven by `xdotool` sending keys and mouse moves into the virtual display, and the session reads whatever controller is plugged into the machine: on 2026-11-11 a capture came out with the inventory open because the user played another game with the same controller. The user (2026-11-11): headless runs "should not" read any physical controller, "it shouldn't respond to keyboard and mouse either. Only injected commands make sense", and "let's shed the xdotool dependency and have the game have a way to inject instead, like a command socket API".

## Goal

Every screen of the game can be driven and captured through the command socket alone, and a session started for that reads no physical device.

## Controls

None for the player: no binding is added or changed. The command socket gains input commands (the design names them), which act where a device's input would: an action pressed, held and released, the sticks and the triggers set, the pointer moved and clicked, text typed into a string field.

## Change

- Input commands on the socket, entering the game where a backend's input does, so the UI's focus navigation, the pointer and the world actions take them as they take a gamepad's. They follow the socket's rule for the simulation: what changes the world goes through the local player's input record.
- A way to start a session that reads no keyboard, mouse or controller, only the socket (an input backend of its own beside `sdl3` and `raylib`).
- `tools/moc` and `doc/commands.md` follow; the capture recipes in the docs name no `xdotool`.

## Verify

- The checks and the suite, with tests that drive a menu and a world action by injected input alone.
- A capture of a screen reached only by injected input (the inventory view's Recipes tab), from a session started with the new backend while a controller is plugged in.

## Specification (design, 2026-11-11)

Designed on `main` at 343618d. No binding, data key, string key, save or record change.

### The seam

The injected input is device state: `Injected_Input`, a virtual gamepad in SDL3's numbering, a keyboard and a mouse, kept on `Frame_Interaction` as the input commands leave them. Under `--input=none` the first viewport's frame is built from it alone by `read_injected_input_frame`, which runs `read_sdl3_input_frame`'s steps on it: the touch overlay merged in, the sticks through the deadzone, the bindings' tables, `actions_just_pressed`. From there everything is unchanged: `make_ui_input` (focus navigation, confirm, the pointer, typed text, the Enter and Backspace edges, the letter wheel's keys), the world action guard, `world_input`, the tick accumulator and the input record take it as a device's. A world action reaches the simulation only in the local player's record, as a gamepad's does; `Record_Input` is untouched.

Rejected:
- Actions pressed into the frame (`apply_touch_overlay_hotbar`'s way): no control behind them, so Confirm comes without the Jump its button also carries, and every raw reader (typed text, Enter and Backspace, the pointer, the glyph device) needs a path of its own.
- A virtual gamepad alone (the touch overlay's seam): no text, no pointer, no keyboard-only action (Open_Recipes, the F keys, Hotbar_Slot_N), so a second seam is needed anyway.

Glyphs: the virtual gamepad is not `on_screen`, so `detect_input_device` reads it as any pad: a button edge or a stick past the deadzone shows the gamepad's glyphs, a trigger does not (it reads button edges and the first four axes); a held key, a pointer move or a click shows the keyboard's and mouse's. Typed text and releases change nothing. Before the first input the UI's default holds (`Keyboard_Mouse`). `press gamepad GUIDE`, bound to nothing in `data/bindings.sjson`, turns the gamepad's glyphs on without an action (question 1).

### The none backend

`--input=none` reads no keyboard, mouse or controller:
- SDL is never initialised (`start_input_backend` skips `init_sdl3_input`): no joystick or gamepad subsystem, no device opened, no rumble, no pad events polled, no `sdl.Quit`.
- No raylib reader runs: `read_raylib_gamepad`, `read_raylib_mouse`, `read_raylib_keyboard` (with its character queue), `keyboard_mouse_actions` and `keyboard_move` are not called. raylib keeps polling the window's events into its own state; nothing of the game reads it.
- The cursor is never disabled (`apply_cursor_mode` returns), so the window never grabs a pointer.
- No system keyboard (`system_keyboard_available` false): a text field draws the game's keys.
- The touch overlay, when on, takes the virtual pointer as its touch point 0 while the virtual left button is held (`read_touch_points`' desktop rule).
- `input_backend` is `.Sdl3`, the numbering of the virtual gamepad: the bindings tables, the glyphs and the F3 Input page read as on sdl3 (the page names the gamepad `Command socket` and still says `backend Sdl3`). One viewport only: no pad joins without SDL.
- It needs developer mode (the socket is its only input) and the socket (not on Windows); either missing exits 2. Android never sees the flag (no command line).
- The input commands answer `error input commands need --input=none` under sdl3 and raylib: no mixing. A virtual pointer and a physical mouse have no common position, both backends read the keyboard's actions straight from raylib, and the tick command's input rule below stays with one backend. `query ui` reads on every backend.

### Commands

A target is an `Action` name (`Confirm`) or `<gamepad|keyboard|mouse> <control>` in the bindings vocabulary: SDL button names and `LEFT_TRIGGER`, `RIGHT_TRIGGER`; raylib key names; raylib mouse button names (not the wheel words). An action resolves through the effective bindings to its first gamepad control the backend reads (the one its glyph shows), else its first key or mouse button; the answer names the control. A pressed control carries every action bound to it, as a device's does (Confirm's SOUTH is Jump in the world).

| Line | Bounds | Answer |
|---|---|---|
| `press <target> [frames]` | frames 1 to 600 (`MAXIMUM_PRESS_FRAMES`), default 1; refused while the control is held | `ok pressed gamepad SOUTH (Confirm) for 1 frame` (`frames` from 2) |
| `hold <target>` | at most 16 keys held (`RAW_KEYS_DOWN_CAPACITY`) | `ok holding gamepad SOUTH (Jump)` |
| `release <target>`, `release all` | the control must be held; `all` lets go of every control, rests the sticks and triggers, drops untyped text, keeps the pointer | `ok released gamepad SOUTH (Jump)`, `ok released all` |
| `stick <left\|right> <x> <y>` | each -1 to 1, up to three decimals (`parse_ranged_decimal_word`), x right, y up; held until set again | `ok stick left at 0.500 -1` (`thousandths_text`) |
| `trigger <left\|right> <value>` | 0 to 1, up to three decimals | `ok trigger right at 1` |
| `pointer <x> <y>` | integers, 0 to the render width or height minus 1 | `ok pointer at 960 540` |
| `type <text>` | one word (quoted for spaces), 1 to 512 characters (`MAXIMUM_TYPED_TEXT_LENGTH`), each space to `~` | `ok typed 9 characters` |
| `query ui` | no argument | below |

Errors, exactly: `input commands need --input=none`; `usage: <the row's usage>`; `unknown action or device "<word>"`; `<Action> is bound to no gamepad control, key or mouse button`; `<device> <control> is no control of the virtual devices` (an unknown name, a wheel word, `trackpad`); `<label> is held; release it first`; `<label> is not held`; `16 keys are held already`; the range messages of `parse_ranged_word` and `parse_ranged_decimal_word` (`the frames`, `x`, `y`, `the trigger`); `the text holds 1 to 512 printable ASCII characters`. An error changes nothing and answers at once.

`query ui` (every backend, no world needed), the first viewport after its last UI pass:
```
ui
screens pause settings        (bottom to top, Screen names in lower case; screens none)
top settings                  (top none)
device gamepad                (or keyboard_mouse: the glyphs shown)
pointer 200.0 100.0 mouse     (render pixels; none, mouse, trackpad or touch)
focus 20 40 200 80            (the focused widget's rectangle in render pixels, rounded; focus none)
text_field closed             (open while a text field takes typed text)
backend none                  (sdl3, raylib or none)
```

Rules:
- The pointer is in the screenshot's pixels (render pixels, the window's on X11), origin top left, starting at 0 0. A move is the mouse's delta for one frame: over a screen it moves the UI's pointer, in the world it turns the view as a mouse does (`look` frames a shot). `press mouse LEFT` clicks where it is.
- `type` fills the frames' typed text, 16 characters a frame; only an open text field takes it, and it holds no key. `press keyboard <key>` holds a key and types no character. `press keyboard ENTER` ends an entry (Enter is Confirm too, as on a keyboard), `press keyboard BACKSPACE` deletes a character.
- `press` is a press of frames, made for the screens. A world action that reads the held control (walking's Jump, Mine, Place) takes `hold`, `tick <n>`, `release` in a stepped session.

### Timing

- Order of a frame (`update_frame`): the input read, the ticks, the socket, then the UI in `render_frame`. A line executed at frame N changes the virtual devices; frame N+1's read takes the change.
- An input command answers once a frame's UI has seen its last change: `press` three frames after it runs (down, up, the UI pass of the release, so a tap's activation on release is done), the others two, `type` one more per 16 characters. Later lines wait behind it, as behind a tick command. A `query ui` or `screenshot` after it sees the result.
- Ticks follow the wall clock while the session runs. While only the socket's `pause` holds them (no pausing screen open on the first viewport), the frames' presses and pointer moves wait in the tick input instead of being dropped, and a `tick <n>` under `--input=none` runs its ticks from the first viewport's world input the way a frame's ticks run: each stamped as a record (`stamp_viewport_records`), the held controls on every tick, the waiting events on the first, through `deliver_records_alone` and `run_ready_ticks`. So `hold Mine`, `tick 120`, `release Mine` holds Mine for exactly 120 ticks. A pausing screen still drops the events. Under sdl3 and raylib `tick` keeps taking no input, so a controller the machine sees moves nothing between framing lines.
- Online (a joined machine, a host with others) the input commands work frame by frame; `tick` and `pause` stay refused there.

### Files and procedures

`src/input_injected.odin` (new, ui cluster; `core:reflect`, `shared:raylib` and `vendor:sdl3` for their enums only):
- `MAXIMUM_TYPED_TEXT_LENGTH :: TEXT_FIELD_CAPACITY`, `MAXIMUM_PRESS_FRAMES :: 600`, `INJECTED_GAMEPAD_NAME :: "Command socket"`.
- `Injected_Stick :: enum u8 {Left, Right}`; `Injected_Control_Kind :: enum u8 {Gamepad_Button, Gamepad_Trigger, Key, Mouse_Button}`; `Injected_Control :: struct {kind: Injected_Control_Kind, code: i32}` (an `sdl.GamepadButton`, a `Gamepad_Trigger`, a raylib key code or an `rl.MouseButton`).
- `Injected_Input :: struct`: `buttons: [RAW_GAMEPAD_BUTTON_CAPACITY]bool`, `sticks: [Injected_Stick][2]f32` (y up), `triggers: [Gamepad_Trigger]f32`, `keys: [RAW_KEYS_DOWN_CAPACITY]i32`, `key_count: int`, `mouse_buttons: [RAW_MOUSE_BUTTON_CAPACITY]bool`, `pointer: [2]f32`, `pointer_delta: [2]f32` (the move the next read takes), `text: [MAXIMUM_TYPED_TEXT_LENGTH]u8`, `text_length: int` (still to type), `press_control: Injected_Control`, `press_frames: int` (reads before the press's control goes up, 0 for none), `unread: bool` (a change no read has taken), `quiet_read: bool` (the last read found no change).
- `injected_control_of :: proc(device: Binding_Device, name: string) -> (control: Injected_Control, ok: bool)`: a trigger name, an SDL button (`sdl_gamepad_button_from_name`), a key (`keyboard_key_from_name`), an `rl.MouseButton` name; false for the wheel words, a trackpad, an unknown name.
- `injected_control_down :: proc(injected: Injected_Input, control: Injected_Control) -> bool`.
- `set_injected_control :: proc(injected: ^Injected_Input, control: Injected_Control, down: bool) -> (ok: bool)`: a button set, a trigger to 1 or 0, a key added once or removed with the order kept; false when a 17th key would be added.
- `release_injected_input :: proc(injected: ^Injected_Input)`: every control up, sticks and triggers at rest, text and press dropped, pointer kept.
- `note_injected_change :: proc(injected: ^Injected_Input)`: `unread = true`.
- `injected_raw_input :: proc(injected: Injected_Input) -> Raw_Input`: backend `.Sdl3`; the gamepad `connected`, named `INJECTED_GAMEPAD_NAME`, `axis_count = TOUCH_OVERLAY_AXIS_COUNT`, `button_count = TOUCH_OVERLAY_SDL_BUTTON_COUNT`, `button_down = buttons`, the stick axes with y negated (SDL's y is down), the trigger axes; `keys_down` and `key_count` from `keys`; `text` the first `min(text_length, RAW_TEXT_CAPACITY)` characters; the mouse at `pointer` with `delta = pointer_delta`, `button_count = len(rl.MouseButton)`, `button_down = mouse_buttons`, no wheel.
- `held_key_move :: proc(keyboard: Raw_Keyboard) -> [2]f32`: W, A, S, D as `keyboard_move` reads them, from `keys_down`.
- `held_keyboard_mouse_actions :: proc(keyboard: Raw_Keyboard, mouse: Raw_Mouse, bindings: Input_Bindings, overlay: Touch_Overlay_Frame) -> Action_Set`: `bindings.keys` of each held key, and unless `touch_overlay_drives_world(overlay)` `bindings.mouse_buttons` of each held button: `keyboard_mouse_actions` without raylib (the claimed left button is already up, `touch_overlay_mouse`).
- `read_injected_input_frame :: proc(injected: Injected_Input, previous_pressed: Action_Set, bindings: Input_Bindings, overlay: Touch_Overlay_Frame) -> Input_Frame`: `injected_raw_input`, `touch_overlay_gamepad(raw.gamepad, overlay, .Sdl3)`, `touch_overlay_mouse`; `move = clamp_to_unit_length(gamepad_stick(raw.gamepad, .LEFT_X, .LEFT_Y) + held_key_move(raw.keyboard))` and `look` from `.RIGHT_X, .RIGHT_Y` (raylib's first four axes are SDL's, `STICK_AXIS_COUNT`); `look_delta = pointer_look_delta(raw.mouse.delta, overlay)`; `pressed` from `gamepad_button_actions`, `gamepad_trigger_actions`, `held_keyboard_mouse_actions`, `analog_actions`; `just_pressed = actions_just_pressed(previous_pressed, pressed)`.
- `advance_injected_input :: proc(injected: ^Injected_Input)`, after each read: `quiet_read = !unread`, `unread = false`, `pointer_delta = {}`, the read characters dropped from `text` (`unread` again while any are left), a press counted down (at 0 its control goes up and `unread` is set).
- `injected_input_settled :: proc(injected: Injected_Input) -> bool`: `!unread && quiet_read && press_frames == 0 && text_length == 0`.
- `injected_touch_points :: proc(injected: Injected_Input, buffer: []Touch_Point) -> []Touch_Point`: `{id = 0, position = pointer}` while the left mouse button is held, else none.

`src/command_input.odin` (new, tools cluster):
- `INPUT_NEEDS_NONE_PROBLEM :: "input commands need --input=none"`.
- `Command_Input_Context :: struct {injected: ^Injected_Input, ui: ^Ui_State, bindings: []Binding, backend: Input_Backend, devices_off: bool, render_size: [2]int}`: the first viewport's virtual devices and UI, the effective bindings and their numbering; zero in a tick's context, where no input line runs.
- `command_reads_input :: proc(name: string) -> bool`: the seven input commands.
- `resolve_action_control :: proc(bindings: []Binding, action: Action, backend: Input_Backend) -> (control: Injected_Control, binding: Binding, found: bool)`: the first binding of the action with `binding_on_backend` and `binding_on_device(.Gamepad)` that `injected_control_of` takes, else the first on `.Keyboard_Mouse`.
- `parse_input_target :: proc(input: Command_Input_Context, words: []string) -> (control: Injected_Control, label: string, rest: []string, problem: string)`: the device form (label `gamepad SOUTH`) or an action (label `gamepad SOUTH (Confirm)`).
- `command_press`, `command_hold`, `command_release`, `command_stick`, `command_trigger`, `command_pointer`, `command_type`, each `:: proc(input: Command_Input_Context, arguments: []string) -> (answer, problem: string)`, changing the devices only without a problem. `pointer` sets `pointer_delta = new - pointer` before `pointer = new`.
- `execute_input_command :: proc(command_context: Command_Context, name: string, arguments: []string) -> Command_Response`: `INPUT_NEEDS_NONE_PROBLEM` unless `devices_off`; the command; on success `note_injected_change`, `control.input_waiting = true`, `control.input_answer = strings.clone(answer)`, `{ok = true, deferred = true}`.
- `query_ui :: proc(input: Command_Input_Context, arguments: []string) -> Command_Response`: the lines above; the focus from `widget_index(ui.widgets[:], ui.focus)`, units times `pixels_per_unit`; names through `strings.to_lower(fmt.tprint(...))`; `backend` is `none` under `devices_off`, else `backend_names`.

`src/command.odin`:
- `Command_Control` gains `input_waiting: bool`, `input_client: u64`, `input_answer: string` (owned).
- `Command_Context` gains `input: Command_Input_Context`.
- `execute_command`: before the world check, the seven names go to `execute_input_command`, and `query ui` to `query_ui` beside `query textures`. `command_writes_simulation` stays false for them.
- `command_usages` gains eight rows (`press <action> [frames] | press <gamepad|keyboard|mouse> <control> [frames]`, `hold ...`, `release ... | release all`, `stick <left|right> <x> <y>`, `trigger <left|right> <value>`, `pointer <x> <y>`, `type <text>`, each summary starting `--input=none:`; `query ui`). `command_query`'s usage adds `ui`.

`src/loop.odin`:
- `Frame_Interaction` gains `injected: Injected_Input` and `input_devices_off: bool`, commented: with it set `input_backend` is only the numbering (`.Sdl3`), SDL is not initialised and no device is read, so nothing that calls SDL or reads raylib's input may run.
- `read_input_frame`: under `input_devices_off`, viewport 0's frame is `read_injected_input_frame(state.interaction.injected, previous.pressed, state.interaction.input_bindings, overlay)` followed by `advance_injected_input`; any other viewport reads `Input_Frame{}`.
- `update_viewport_pads` returns under `input_devices_off`; `update_frame`'s haptics loop does nothing under it; `apply_cursor_mode` returns under it.
- `run_game`: `state.interaction.input_devices_off` from `player_configuration`; `shutdown_sdl3_input` only without it; `system_keyboard_available = !input_devices_off && system_keyboard_available()`.
- `frame_events_dropped :: proc(holding, pausing_screen, devices_off: bool) -> bool`: `holding && (pausing_screen || !devices_off)`. `update_session` takes `paused_frame_input` when it is true (`pausing_screen` = `ui_pauses_simulation(state.viewports[0].interaction.ui.screens)`), else `accumulate_frame_input`.
- `run_command_input_ticks :: proc(state: ^Frame_State, content: Simulation_Content, worlds: []Input_Frame, answers: ^[dynamic]Line_Answer) -> int`, called by `update_session` instead of `run_command_ticks` under `input_devices_off`, `send_line_answers` moved after that block:
  ```
  for control.pending_ticks > 0 && time.tick_since(start) < COMMAND_TICK_WALL_BUDGET {
      if !simulated_chunks_ready(&session.simulation) { break }
      stamp_viewport_records(state, worlds) // false while the next record waits to run
      deliver_records_alone(session)
      ran := run_ready_ticks(session, content, control, answers)
      if ran == 0 { break }
      control.pending_ticks = max(control.pending_ticks - ran, 0)
      count += ran
  }
  ```
- `frame_command_context`: `input = {&state.interaction.injected, primary_ui(state), state.interaction.bindings, state.interaction.input_backend, state.interaction.input_devices_off, render_size()}`.
- `execute_queued_command`: a deferred answer sets `command_control.input_client` when `command_reads_input(words[0])`, `tick_client` otherwise.
- `answer_input_command :: proc(state: ^Frame_State)`: once `input_waiting` and `injected_input_settled`, `send_logged_response(state, input_client, "input", command_ok("%s", input_answer))`, the answer freed, the three fields cleared. `serve_command_socket` calls it after `answer_command_ticks` and takes no line while `input_waiting`. `destroy_command_frame_state` frees `input_answer`.

`src/touch_overlay.odin`: `read_touch_overlay_frame` takes its points from `injected_touch_points(touch_context.interaction.injected, buffer[:])` under `touch_context.interaction.input_devices_off`, else `read_touch_points`.

`src/main.odin`:
- `Input_Backend_Request` gains `None`; `parse_input_request("none")`; the unknown backend message lists `--input=none`; the flag's usage `input backend: sdl3, raylib or none (only the command socket's input commands, needs developer mode); default SDL3 with raylib fallback`.
- `start_input_backend`: `.None` logs `input: none backend (requested with --input=none): no keyboard, mouse or controller is read, only the command socket's input commands` and returns `.Sdl3, true`.
- `input_none_problem :: proc(request: Input_Backend_Request, developer_flag, developer_setting, socket_supported: bool) -> string`: `--input=none reads only the command socket, which the Windows build lacks`, or `--input=none reads only the command socket, which needs developer mode (--dev or the Developer mode setting)`, else "". `game_main` calls it once the configuration loaded, with `COMMAND_SOCKET_SUPPORTED` and the loaded `developer_mode`, and exits 2 on a problem.
- `Player_Configuration.input_devices_off = input_request == .None`.

`src/configuration.odin`: `Player_Configuration.input_devices_off: bool` (`--input=none`, 0341).

### Tests

Shipped bindings through `shipped_default_bindings(t)`, tables from `build_input_bindings(..., .Sdl3, context.temp_allocator)`. A read is `read_injected_input_frame` then `advance_injected_input`.

`src/input_injected_test.odin`:
- `test_a_press_reads_down_for_its_frames_and_settles_after_its_release`: SOUTH down with `press_frames = 2`: reads 1 and 2 hold Confirm and Jump in `pressed` and SOUTH in `raw.gamepad.button_down`, Confirm in `just_pressed` on read 1 only; read 3 neither; settled after read 4, not after reads 1 to 3.
- `test_typed_text_reaches_sixteen_characters_a_frame`: 40 characters arrive as 16, 16 and 8 in order with `key_count` 0; settled after read 4 only.
- `test_the_virtual_devices_set_the_glyph_device_as_devices_do`: `detect_input_device` over reads: a button edge gives `.Gamepad`; a pointer move `.Keyboard_Mouse`; typed text alone nothing seen; a held key `.Keyboard_Mouse`; a stick at (0, 0.1) nothing, at (0, 1) `.Gamepad`.
- `test_sticks_triggers_keys_and_buttons_reach_the_frame`: left stick (0, 1) moves (0, 1); right stick (0.1, 0) looks 0; right trigger 1 presses Mine, 0.4 not; key W moves (0, 1); key C presses Open_Recipes; mouse LEFT presses Mine; a pointer move from 0 0 to 300 200 gives `look_delta` (300, 200) and the position, the next read a delta of 0.
- `test_the_touch_overlay_takes_the_virtual_pointer_as_its_touch`: `injected_touch_points` gives no point with the left button up, point 0 at the pointer with it held.

`src/command_input_test.odin`, with helpers `injected_command_context` (a `Command_Context` over a frame state's devices, its UI, the shipped bindings, `.Sdl3`, `devices_off`, render 1920 by 1080, its session's simulation and the frame's `command_control`), `run_injected_test_frame` (viewport 0's input read with `read_input_frame`, then `update_frame_world`) and a screen variant over `screen_test_frame` with `make_ui_input`; each runs a line, then frames until `injected_input_settled` (at most 64), and clears `input_waiting` as the loop's answer does:
- `test_an_action_presses_its_first_gamepad_control_else_its_key`: Confirm resolves to SOUTH, Mine to the right trigger, Open_Recipes to key C, Open_Aimed to nothing; over `effective_bindings` with Confirm on keyboard ENTER alone, Confirm resolves to ENTER.
- `test_input_commands_answer_once_a_frame_saw_their_last_change`: the answers of the table for `press Confirm` (settled after the third read), `hold Jump` (second), `release Jump`, `stick left 0.5 -1`, `pointer 960 540`, `type "Deep mine"`; each deferred with `input_waiting` set.
- `test_input_commands_refuse_what_the_virtual_devices_cannot_do`: every error of the Commands section answers at once with `input_waiting` false and the devices unchanged: any command without `devices_off`, `press Confirm 0`, `press Confirm 601`, `stick left 1.001 0`, `stick up 0 0`, `trigger right -0.1`, `pointer 1920 0`, `pointer 0 -1`, `type ""`, 513 characters, `type "café"`, `type a b`, `release Confirm` while up, `press gamepad MISC9`, `press mouse WHEEL_UP`, `press trackpad LEFT`, `press Open_Aimed`, `press Confirm` while held, a 17th held key.
- `test_query_ui_names_the_screens_focus_pointer_and_device`: Pause under Settings, `pixels_per_unit` 2, a widget 9 at {10, 20, 100, 40} focused, `.Gamepad`, the pointer at (100, 50) from the mouse, `devices_off`: the seven lines of the example exactly; a zero `Ui_State` gives `screens none`, `top none`, `device keyboard_mouse`, `pointer 0.0 0.0 none`, `focus none`.
- `test_injected_navigation_drives_the_pause_menu` (UI audit, `open_pause_menu`): `press Navigate_Down` moves the focus off `pause_button_id("pause_resume")`; further presses reach `pause_settings` within ten; `press Confirm` puts `.Settings` on top, `press Back` `.Pause`; `active_device` stays `.Gamepad`.
- `test_an_injected_click_on_a_widget_activates_it` (UI audit): `pointer` at `widget_centre` of `pause_developer`, `press mouse LEFT`: `.Developer` on top, `active_device` `.Keyboard_Mouse`.
- `test_injected_text_types_into_the_new_world_name` (UI audit, `open_new_world_name_entry(audit, &state, false)`): `type "Deep mine"` sets the name; `press keyboard ENTER` closes the entry (`keyboard.field == 0`) with the name kept and `.New_World` on top.
- `test_an_injected_jump_lifts_the_player_through_the_input_record` (`make_viewport_test_frame`, `input_devices_off`, the shipped bindings and tables, until ready): `hold Jump`, ten frames: the debug terrain's flying player rose and ten ticks ran.
- `test_a_tick_command_runs_with_the_held_input_under_the_none_backend`: same frame; `pause`, `hold Jump` (the tick does not move); `tick 10` through frames until `pending_ticks` is 0 (at most five): ten ticks ran and the player rose; `release Jump`, `tick 10`: ten more, the height unchanged (fly mode has no gravity).
- `test_frame_events_wait_for_the_tick_only_under_the_none_backend`: `frame_events_dropped` is false not holding, true with a pausing screen, true held by the socket on a device backend, false held by the socket under none.
- `test_the_none_backend_reads_the_virtual_devices_alone` (the viewport frame, `input_devices_off`, SOUTH held and noted): `read_input_frame(state, 0, ...)` gives a gamepad named `INJECTED_GAMEPAD_NAME` with Confirm pressed, and `unread` is false after. It stands for the item's "a key pressed in raylib's state is ignored", which no headless test can set up: raylib presses no key without a window.

`src/main_test.odin`:
- `test_input_none_is_parsed_and_needs_developer_mode_and_the_socket`: `parse_input_request("none")` is `.None`; `command_line_value_problem` accepts `--input=none` and names it in the unknown backend message; `input_none_problem` gives the developer mode message with neither flag nor setting, the Windows message without the socket, "" with either developer source, "" for `.Sdl3`.

### tools/moc

- The docstring names `--input=none` and the seven input commands (doc/commands.md, Input).
- `tools/moc --until <regular expression> <words...>`: sends the command once, then again after each answer until a line of an answer matches (`re.search`), at most 600 times (`UNTIL_TRIES`); prints the last answer; exit 0 on a match, 1 on an error answer or when the tries ran out (a line on stderr), 2 on a bad expression or a missing socket. Each try lands in a later frame, since the game reads the socket once a frame, so `tools/moc --until '^top recipes$' query ui` waits for a screen without a sleep. No Python test: a loop over `send_lines`' pieces, exercised by the Verify's capture.

### Docs

- `doc/commands.md`: the third bullet of the head names the input commands as neither kind (they set the virtual devices the frames read; a world action rides the record as a device's); For the assistant: a headless capture starts with `--dev --input=none` under Xvfb, and `--until`; Protocol: the input commands and `query ui` need no world; the Commands table gains the eight rows and the `tick` row its input rule; a new section `## Input` with the Commands section's targets, bounds, rules and Timing; The field world's framing bullet ends with `--input=none` instead of "a gamepad the machine sees"; Multiplayer: the input commands work on a joined machine.
- `doc/input.md`: the head bullet names three backends; the Backends table gains `none` (`input_injected.odin`, the command socket's virtual devices, `--input=none` with developer mode); a subsection `### The none backend` with the list of The none backend above and the glyph rule; The input frame: the events wait for the tick under none while only the socket's pause holds the ticks.
- `doc/build.md`: the Command line row `--input=sdl3`, `--input=raylib`, `--input=none`; What the Windows build lacks: `--input=none` exits 2.
- `doc/touch_overlay.md`, When it is on: every backend, under `--input=none` the socket's pointer as the touch.
- `doc/code_map.md`: `input_injected.odin` in the ui files, `command_input.odin` in the tools files, the counts the two checks report.
- `SUGGESTIONS.md`: the entry on a headless game taking the user's Steam Controller (`--no-gamepad`) goes; `--input=none` settles it.

### Hand-back check lines that apply

- A number parsed from text is range checked: frames, stick and trigger values, pointer coordinates through `parse_ranged_word` and `parse_ranged_decimal_word`; no `strconv`.
- A list that grows without bound is capped: the text at 512, the held keys at 16, one press and one waiting answer at a time.
- Tests never touch the state directory: every test runs in memory, no screenshot, no socket.
- Memory a frame may draw from: none is freed; `input_answer` is freed in the socket's serve step and never drawn.

### Decisions taken

1. Raw device state over actions or a gamepad alone (The seam).
2. `Input_Backend` keeps its two values as the raw gamepad's numbering and `input_devices_off` marks the none backend. A third enum value would need a numbering mapping in `build_input_bindings`, `backends_from_name`'s default set, `binding_on_backend`, the overlay's numbering, the diagnostics labels and the `{.Raylib, .Sdl3}` comparisons of the Controls list.
3. No mixing with sdl3 or raylib (The none backend).
4. `tick` takes input under none alone, and the socket's pause keeps the frames' events there (Timing): the stepped session is the deterministic way to hold a world action for an exact tick count, and under the device backends it keeps today's promise.
5. Answers after the UI pass of the frame that read the last change, so a following query or screenshot sees the effect, a tap on release included.
6. The pointer in render pixels, the screenshot's, so a script points at what it saw in a capture.
7. Waiting for a state is `query ui` polled with `tools/moc --until`, frame paced; no wait command in the game.
8. No wheel, touchpads, gyro or touch sense on the virtual devices: every screen is reached by focus navigation and the pointer.

### Questions to the main agent

1. Glyphs before the first injected input are the keyboard's (the UI's default), and `press gamepad GUIDE` switches to the gamepad's. Should `--input=none` start on the gamepad's glyphs instead, couch first?
2. For the Verify's capture: start under Xvfb with isolated XDG directories and `--dev --input=none --seed=<n> --name=<world>`; `tools/moc pause`, `tick` past the fall, `seat stand` (the chair takes X while seated, 0223), `look` where no panel is aimed, `press Open_Inventory`, `press Tab_Next`, `tools/moc --until '^top recipes$' query ui`, `screenshot`. The log shows `input: none backend` and no `input: opened gamepad` or `SDL sees` line. The capture recipe in the screenshots memory (xdotool, `SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT`) is yours to replace once this lands.

### Decisions (main agent, 2026-11-11)

1. `--input=none` starts on the gamepad's glyphs: the game is gamepad first and a capture should show what the couch shows. A held key, a pointer move or a click switches to the keyboard's and mouse's as on a device, and `press gamepad GUIDE` back. A test asserts the glyph device before the first injected input.
2. The capture recipe is as written. The memory note is the main agent's at the landing.
3. Every build or test run of the implementer goes inside `systemd-run --user --scope --quiet -p MemoryMax=8G -p MemorySwapMax=0`.

### Deviations (implementation, 2026-11-11)

- `doc/commands.md`: each input command's bounds stand in its row of the Commands table, as every other command's do, and `## Input` holds the targets, the rules, the errors, `query ui` and Timing without repeating them (one place per fact).
