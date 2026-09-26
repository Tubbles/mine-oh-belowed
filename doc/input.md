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

## Generic gamepads

Post alpha. The action layer supports any pad, but the trackpad only actions (radial hotbar, letter wheel) need stick and button equivalents before an Xbox style controller is fully usable.
