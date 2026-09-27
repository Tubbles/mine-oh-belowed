# Input

## The controller

Steam Controller (2026), released 2026-05-04. Inputs: two clickable TMR thumbsticks with capacitive touch, two square haptic trackpads (touch, position, pressure, click), a six axis IMU (gyroscope and accelerometer), four rear grip buttons (L4, L5, R4, R5), capacitive grip sense on both handles, A B X Y, d-pad, L1 and R1 bumpers, L2 and R2 analog triggers, and the Steam, Quick Access, View and Menu buttons. Connectivity: 2.4 GHz puck, Bluetooth, USB-C. The Steam and Quick Access buttons belong to Steam.

## Technical path

Facts established 2026-09-26:

- raylib reads gamepads through GLFW: sticks, buttons and triggers of a standard pad. No trackpads, gyro, grip buttons or pressure.
- The Steam Input API (Steamworks) exposes action sets, `GetMotionData` and trackpad modes, but it needs a Steam app id the account owns. A non-Steam shortcut cannot initialise it. Non-Steam games receive an emulated XInput pad plus keyboard and mouse events from Steam Input.
- SDL3 has a HIDAPI driver for this controller (`src/joystick/hidapi/SDL_hidapi_steam_triton.c`) that exposes gyro, trackpads with position and pressure, capacitive stick touch, grip sense and the grip buttons. The expanded support (SDL pull request 15528, merged 2026-05-14) is present in SDL 3.4.16, which is both the host version and the nixpkgs version. SDL only sees the controller when Steam Input is not claiming it.
- Odin ships `vendor:sdl3`, linked against the system `libSDL3.so`.
- The couch machine has udev rules granting user access to Valve controllers over hidraw (`/usr/lib/udev/rules.d/71-valve-controllers.rules`, vendor id 28de).

Chosen path, pending the spike in work item 0002: read the controller directly with SDL3, launched from Steam with Steam Input disabled for the shortcut. Fallback: the Steam Input translation layer (gyro to mouse, right pad to mouse, left pad and grips to keys) read through raylib. The fallback loses trackpad position, which the radial menus need, so it is a fallback only.

Spike questions: does SDL3 see the controller while Steam is running with Steam Input disabled for the game, over puck and Bluetooth; poll rate and latency; gyro units and axis frame; trackpad coordinate range, pressure and click; grip sense; the haptics API for the pads; behaviour while the Steam overlay is open.

### How SDL3 exposes the controller

Read from the SDL `release-3.4.16` sources on 2026-09-27: `src/joystick/hidapi/SDL_hidapi_steam_triton.c` (the driver, line numbers below refer to it unless stated), `src/joystick/hidapi/steam/controller_structs.h`, the Triton mapping string in `src/joystick/SDL_gamepad.c` (branch `SDL_IsJoystickSteamTriton`) and `include/SDL3/SDL_sensor.h`. The host `/usr/lib64/libSDL3.so.0` contains both the driver (its rumble error string) and the Triton mapping string. Nothing below has been observed on hardware yet.

- **Driver enable.** `HIDAPI_DriverSteamTriton_IsEnabled` (lines 427 to 431) reads `SDL_HINT_JOYSTICK_HIDAPI_STEAM` and falls back to the general HIDAPI default, so the driver is on without any hint. The header documents the hint's default as off, but that text describes the first Steam Controller over Bluetooth. The game sets the hint to `1` anyway so the two cannot disagree.
- **Device.** Named "Steam Controller" (line 468). A wired controller connects at once. Through the puck (Proteus or Nereid dongle, interfaces 2 to 5) the gamepad only appears once the dongle reports a wireless connect or the first state packet arrives (lines 400 to 413, 530 to 554). While a gamepad is open the driver turns lizard mode (the controller's own keyboard and mouse emulation) off every 3 seconds (lines 499 to 503).
- **Buttons.** The driver defines 22 joystick buttons (lines 46 to 60, 581). Buttons 0 to 10 follow SDL's standard order. The Triton mapping string turns the rest into gamepad buttons: QAM `MISC1`, R4 `RIGHT_PADDLE1`, L4 `LEFT_PADDLE1`, R5 `RIGHT_PADDLE2`, L5 `LEFT_PADDLE2`, left pad click `TOUCHPAD`, right pad click `MISC2`, left stick touch `MISC3`, right stick touch `MISC4`, left grip touch `MISC5`, right grip touch `MISC6`. Steam is `GUIDE`.
- **Menu and View.** Lines 171 to 174 send the Menu bit to `BACK` and the View bit to `START`, the reverse of the usual convention (View as back, Menu as start). Whether the bit names or the SDL assignment are off is not visible from the source, so the couch test records which physical button lights up `BACK`.
- **Sticks and triggers.** All six SDL axes (line 582). Stick y is negated to match the SDL convention of up as negative (lines 230 to 237). Triggers are rescaled from 0..32767 to the SDL range (lines 226 to 229). The report also carries trigger click bits (lines 93, 98) that the driver never forwards.
- **Capacitive stick touch and grip sense.** Plain digital buttons, see the mapping above (lines 199 to 207). No analog value.
- **Trackpads.** SDL touchpad API, two touchpads with one finger each (lines 588 to 589): index 0 is the left pad, index 1 the right pad (lines 253 to 276). Position is `raw / 65536 + 0.5` on x and `-raw / 65536 + 0.5` on y, so both run 0 to 1 with the origin at the top left, assuming the raw values span the full signed 16 bit range. Pressure is the unsigned 16 bit raw value divided by 32768, so the nominal range is 0 to 2; the source does not say how far the hardware goes. On lift the driver sends one update with `down` false and the last position. Touch without click comes only through the touchpad `down` flag; click comes only through the buttons above.
- **Gyro and accelerometer.** SDL sensor API, `SDL_SENSOR_GYRO` and `SDL_SENSOR_ACCEL`, registered at 1000000 / 4032 ≈ 248 Hz (lines 40 to 41, 576, 585 to 586). They report nothing until enabled with `SDL_SetGamepadSensorEnabled`, which switches the controller's IMU mode (lines 652 to 676). Gyro is in radians per second with a ±2000 degrees per second full scale, accelerometer in metres per second squared with ±2 g full scale (lines 283 to 291). The driver remaps the raw axes into the SDL frame as `(x, z, -y)`. SDL's frame (`SDL_sensor.h`): x right, y up, z toward the player, rotation counter clockwise positive, `values[0]` pitch, `values[1]` yaw, `values[2]` roll. Whether the raw controller axes really match that remap is exactly what the couch test must confirm.
- **Focus.** Without SDL video there are no SDL windows, so SDL never drops joystick events for lack of focus (`SDL_PrivateJoystickShouldIgnoreEvent` in `src/joystick/SDL_joystick.c`). Input keeps arriving while the raylib window is unfocused.
- **Haptics.** Only `SDL_RumbleGamepad` (lines 594 to 623) and raw feature reports through `SDL_SendGamepadEffect` (lines 640 to 650). No per pad haptics API.

### Couch test checklist

1. Build with `./build.sh`. In desktop mode, from the repository root, run `./build/mine-oh-belowed` once in a terminal (`./bin/mine-oh-belowed` is the launcher of the installed play build, `tools/install_play_build.sh`). Expected on stderr: `input: sdl3 backend (default)`, then `input: opened gamepad <id> "Steam Controller" vendor 28de product <id> path /dev/hidraw<n> touchpads 2` once the controller is on. The line before it says whether Steam Input is on for the launch, from Steam's environment; an evdev path and `touchpads 0` on the gamepad line mean Steam's virtual pad. `--input=raylib` forces the old backend, `--input=sdl3` fails instead of falling back.
2. Disable Steam Input for the shortcut: in the Steam library open the shortcut's Properties, Controller, and set the override to "Disable Steam Input". Then launch the game from Steam. Stderr is not visible there; the diagnostics screen shows `backend Sdl3` in the first column.
3. Middle column: header `gamepad <id>: Steam Controller`. Right column: `touchpads 2`, `touch sense available`, both sensors `has yes on yes` near 248 Hz. `touchpads 0` or `touch sense not reported` means SDL sees Steam's virtual pad instead of the controller, so Steam Input is still on. The same shows in the log as `gamepad has no GYRO sensor`. Without the diagnostics screen, three tells outside the game say Steam Input is on while it runs: `/proc/bus/input/devices` lists `Microsoft X-Box 360 pad 0` (Steam's virtual pad, vendor 28de product 11ff), the game's environment carries `SDL_GAMECONTROLLER_IGNORE_DEVICES` with `0x28de/0x1302` and `0x28de/0x1303` and `SteamVirtualGamepadInfo` naming `~/.local/share/Steam/config/virtualgamepadinfo.txt`, and that file relabels the virtual pad as "Steam Controller" 28de:1302, which is why the log names the real controller for a pad without sensors (couch test 1, 2026-09-27).
4. Each input and what should light up:
   - Left stick: `LEFTX`, `LEFTY`, `move`. Up is negative `LEFTY` and positive `move` y. Click: `LEFT_STICK`, `Sprint`.
   - Right stick: `RIGHTX`, `RIGHTY`, `look`. Click: `RIGHT_STICK`.
   - Resting a thumb on a stick without moving it: `MISC3 (L stick touch)` or `MISC4 (R stick touch)` and the matching `stick touched yes`.
   - Holding each handle: `MISC5 (L grip touch)`, `MISC6 (R grip touch)`, `grip touched yes`.
   - Triggers: `LEFT_TRIGGER`, `RIGHT_TRIGGER` from 0 to 1; past half, `Place` and `Mine`.
   - A B X Y: `SOUTH EAST WEST NORTH`; actions Jump and Confirm, Sneak and Back, Open_Inventory, Rotate_Building.
   - D-pad: `DPAD_*`; up also `Pipette`. L1 R1: `LEFT_SHOULDER`, `RIGHT_SHOULDER`.
   - Grips: L4 `LEFT_PADDLE1 (L4)` with Jump and Confirm, R4 `RIGHT_PADDLE1 (R4)` with Sneak and Back, L5 `LEFT_PADDLE2 (L5)` with Rotate_Building, R5 `RIGHT_PADDLE2 (R5)` with Pipette.
   - View and Menu: note which one lights `BACK` (Open_Map) and which `START` (Pause), see the swap above.
   - Steam and QAM: `GUIDE`, `MISC1 (QAM)`, if Steam lets them through.
   - Left pad: finger shows `touchpad 0 finger 0 down` with x and y from 0 at top left to 1 at bottom right, `p` pressure, and `Hotbar_Radial`. Note the highest pressure a hard press reaches. Click: `TOUCHPAD (L pad click)`.
   - Right pad: `touchpad 1 finger 0`; sliding moves `look delta` (right is positive x, down positive y). Click: `MISC2 (R pad click)` and Confirm.
   - Gyro: with a thumb on the right stick or right pad, turning the controller right should give positive `look delta` x and tilting its far end up negative y. At rest `gyro` shows near 0 on all three. Note the sign of each axis for yaw, pitch and roll.
   - Accelerometer: flat on the table, about +9.8 on the second value (y up) and near 0 on the others.
5. Repeat steps 2 to 4 over the puck and over Bluetooth, and once with the Steam overlay open.

## Layout proposal for the alpha

Everything below is a binding table in configuration, not code. Same physical input, two contexts.

| Input | In the world | In menus |
| --- | --- | --- |
| Left stick | Move. Click: sprint toggle | Focus navigation |
| Right stick | Camera, coarse | Scroll lists |
| Gyro | Camera, fine aim. Active while the right stick or right pad is touched; always on and grip sense are settings | Off |
| Right trackpad | Camera as a mouse surface. Click: interact | Pointer. Click: confirm |
| Left trackpad | Radial hotbar: touch shows the wheel, slide to a slot, release selects | Radial letter wheel (first letter jump), radial category wheel |
| R2 trigger | Mine, break | Confirm |
| L2 trigger | Place, use | Secondary action (split stack, transfer all) |
| A | Jump | Confirm |
| B | Sneak (hold) | Back |
| X | Open inventory | Sort |
| Y | Rotate held building | Info panel |
| D-pad | Left and right: hotbar slot. Up: pipette. Down: drop | Focus navigation |
| L1, R1 | Previous and next hotbar slot | Previous and next tab |
| L4, R4 | Jump, sneak (thumbs stay on the sticks) | Same as A, B |
| L5, R5 | Rotate building, pipette | Same as Y, d-pad up |
| View | Map and overview | Close all |
| Menu | Pause menu | Pause menu |
| Steam, Quick Access | Reserved by Steam | Reserved by Steam |

Selection assist: the reticle snaps to the nearest entity in the aim direction, the bumpers cycle between overlapping candidates when several small entities sit under the reticle, and holding Y names everything under it. Factorio's Switch port shows that picking one building among dense neighbours is the remaining weak spot of pad play even after every widget was made stick navigable (see `inspiration.md`). The third person toggle exists for the same reason: a console review of Satisfactory found first person placement harder than it needs to be.

Distribute gesture: holding L2 while sweeping the reticle across machines spreads the held stack evenly over them. Hand feeding is the whole early game and Even Distribution is one of the most installed Factorio mods for exactly this.

R2 to mine and L2 to place mirrors Minecraft Bedrock's controller defaults, so habits transfer for players who know it. The grip buttons duplicate face buttons on purpose: they are the expert copy that keeps the thumbs on the sticks.

## Bindings implemented so far

Bindings live in `data/bindings.sjson` (action, device, control, context, optional backend) since 0025, and the configuration may override the list for an action; the settings screen shows the effective bindings read only. Two bindings are SDL3 only because the raylib table never had them (Sneak on B, Sprint on the stick click). The raylib backend reports the bindings it cannot express once at start. Beyond the layout table above: d-pad left and right and L1 and R1 cycle the selected block (`Hotbar_Previous`, `Hotbar_Next`) on both backends, as do the mouse wheel and the bracket keys. Keyboard only developer actions: F3 diagnostics, F4 the world statistics overlay (0044, off by default), F5 remove a block, F6 fly mode, V camera mode, WASD move, Space jump, Left Shift sneak, Left Control sprint while held (`Sprint_Hold`, 0044; the stick click `Sprint` toggles sprinting until movement stops), Escape pause, E inventory, M map, R rotate, Q or middle mouse pipette, Tab radial. Menu actions since 0009: Confirm (A, R2, Enter), Back (B, Escape and Pause while a screen is open), tab previous and next (L1, R1, keyboard Q, E), Info (Y, keyboard R), Context action (X, keyboard F), list scrolling (right stick, mouse wheel), focus navigation (d-pad, left stick, arrow keys). The right pad click is a pointer click while the pointer is visible and Confirm while it is hidden. In panels (0010, 0011) X sorts the focused container and L2 (Left Shift on the keyboard) splits the focused stack, as the layout table says. Interact opens a targeted machine: A and L4 while an entity is targeted (Jump is dropped for that tick), the right pad click, and F on the keyboard. Holding A with a stack in hand while moving across machine slots distributes it on release. The hotbar radial opens on left pad touch (SDL3) or on held Tab with the right stick (raylib and keyboard), and while it is open the right stick does not turn the camera. The journal (0013) opens with J on the keyboard or from the pause menu. F7 drops an iron plate on the targeted belt (0014), and Rotate with no machine item selected turns a placed belt, inserter or drill. The power overview opens with P or from the pause menu (0020); Interact turns a power switch and Sneak plus Interact opens its panel. The technology screen opens with T, from the pause menu, from the inventory's third tab or from a lab's panel (0021). The statistics screen opens with N or from the pause menu and O toggles the bottleneck overlay (0028); neither has a gamepad button yet. L2 and the right mouse button use a usable item such as a schematic, the geologist's hammer, the magnetometer or a thumper charge (0036, 0038), and Interact on a schematic crate takes and reads it in one press. The magnetometer's strength drives controller rumble on the SDL3 backend; SDL exposes no per pad haptics for this controller, so both motors rumble together. Not yet bound anywhere on a gamepad: the recipe browser and the journal as direct buttons, Drop, Close all. Rotate a held building is Y and R (0011). The recipe browser (0012) opens with C on the keyboard, from the inventory's second tab, or from the pause menu; in it A queues one craft, X or F queue five, L2 or Left Shift cancel the newest, and the letter wheel on the left pad jumps to a letter. Keyboard letters that are menu keys (A, C, D, E, F, Q, R, S, W) do not jump.

## Generic gamepads

Post alpha. The action layer supports any pad, but the trackpad only actions (radial hotbar, letter wheel) need stick and button equivalents before an Xbox style controller is fully usable.
