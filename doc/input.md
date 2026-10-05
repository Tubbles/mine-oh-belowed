# Input

How input reaches the game: devices, backends, bindings and the input frame. How the UI consumes it (focus, pointer, glyphs) is in [ui.md](ui.md); the touch screen's virtual gamepad is in [touch_overlay.md](touch_overlay.md).

- Two backends: SDL3 (the desktop default, the only one that reads the Steam Controller's trackpads, gyro, grips and touch sense) and raylib (fallback, and the only one on Android). Keyboard and mouse always come from raylib, since SDL runs without video.
- Every control reaches the game as an action through `data/bindings.sjson`; the sticks and WASD are not bindings.
- Each frame becomes an `Input_Frame`; the simulation reads only that frame, never the settings or the wall clock.
- The couch runs Steam Input beside the game, so the gyro comes from Steam's layout as mouse movement while SDL reads everything else.

## Backends

`start_input_backend` (`main.odin`) picks the backend at start and logs the choice (`input: sdl3 backend (default)`).

| Backend | Reads | Selected |
| --- | --- | --- |
| SDL3 (`input_sdl3.odin`) | Every gamepad through `vendor:sdl3` (`sdl.Init` with the joystick and gamepad subsystems), up to `SDL3_GAMEPAD_CAPACITY` (8) open at once, each with touchpads, sensors, touch sense, its own gyro calibration and rumble | Default on the desktop; `--input=sdl3` fails instead of falling back |
| raylib (`input_raylib.odin`) | The first of raylib's 4 gamepad slots: sticks, buttons, triggers (as buttons) | `--input=raylib`, when SDL fails to initialise, and always on Android |

- The raylib backend has no paddles, MISC buttons or trackpads. It logs the bindings it cannot express once at start (`unsupported_bindings_report`), so there the hotbar radial comes only from held Tab with the right stick, the keyboard's way on either backend.
- Both backends merge the touch overlay's gamepad into the physical one after reading it (`touch_overlay_gamepad`), so the overlay works on either.
- Android has no SDL: `input_sdl3.odin` is `#+build !linux:android`, `input_sdl3_android.odin` stands in and `init_sdl3_input` fails with "no SDL on Android".

## The input frame

Rule: the input layer puts everything the simulation needs into `Input_Frame`, and the simulation never reads settings.

- `move` (x right, y forward), `look` (stick rate, y up) and `look_delta` (pointer pixels in window coordinates, y down; mouse, right trackpad and gyro add into it), `pressed` and `just_pressed` action sets.
- `apply_hold_settings` sets `sneak_toggles` and `sprint_holds`; `world_input` sets `developer` and `world_blocked`; the touch overlay sets `aim_direction` with `aim_overrides`.
- Frames and ticks run at different rates. `Tick_Input_Accumulator` sums the events (`look_delta`, `just_pressed`, `world_blocked`) over the frames until the next tick takes them; held state (`move`, `look`, `pressed`) is read from the latest frame. While the simulation is paused the events are dropped, but a blocked frame is kept for the first tick after (`paused_frame_input`).
- While a screen is open the world gets none of `WORLD_ACTIONS`. A world action still held when the screen closes stays hidden until released (`update_world_action_guard`), so the A that picked Resume does not also jump.
- `STICK_DEADZONE` (0.15) is radial on both sticks; a trigger presses past `TRIGGER_PRESS_THRESHOLD` (0.5).

## Steam Controller through SDL3

The Steam Controller (2026) adds to a standard pad two haptic trackpads (touch, position, pressure, click), capacitive stick and grip touch, a six axis IMU and rear grips L4 L5 R4 R5; Steam and Quick Access belong to Steam. SDL reads it through its HIDAPI driver `SDL_hidapi_steam_triton.c` (host SDL 3.4.16), with hidraw access from udev (`/usr/lib/udev/rules.d/71-valve-controllers.rules`, vendor 28de). `init_sdl3_input` sets `SDL_HINT_JOYSTICK_HIDAPI_STEAM` to 1, as the hint's documented default is off; the game opens every gamepad SDL adds and enables its gyro and accelerometer; which viewport reads which pad is Split screen below.

The Triton mapping string names the extra inputs (`steam_controller_button_name`):

| Physical | SDL gamepad button |
| --- | --- |
| Steam, Quick Access | `GUIDE`, `MISC1` |
| L4, R4, L5, R5 | `LEFT_PADDLE1`, `RIGHT_PADDLE1`, `LEFT_PADDLE2`, `RIGHT_PADDLE2` |
| Left pad click, right pad click | `TOUCHPAD`, `MISC2` |
| Left stick touch, right stick touch | `MISC3`, `MISC4` |
| Left grip touch, right grip touch | `MISC5`, `MISC6` |

- Touch sense is read from `MISC3` to `MISC6` only on a Valve gamepad that has `MISC6` (`has_steam_controller_touch_sense`), the Triton mapping.
- Trackpads come through SDL's touchpad API: index 0 the left pad, 1 the right (`LEFT_TOUCHPAD_INDEX`, `RIGHT_TOUCHPAD_INDEX`), positions 0 to 1 from the top left. A finger down is the touch, the click is the button above.
- Sensors use SDL's frame: x right, y up, z toward the player, rotation counter clockwise positive; gyro in radians per second, accelerometer in metres per second squared.
- Haptics: SDL has only whole controller rumble for this controller, so both motors play the requested strength (`apply_sdl3_haptics`), renewed every frame for `HAPTIC_RUMBLE_MILLISECONDS` (100); a strength of 0 stops it once. The magnetometer's strength is the only request (`haptic_request_for`).

### Look from trackpad and gyro

- The right pad's finger movement turns the view at `TOUCHPAD_LOOK_PIXELS_PER_PAD_WIDTH` (1200) look pixels per pad width, times the trackpad sensitivity. A finger landing or lifting adds nothing.
- The gyro aims while the right stick or the right pad is touched (`gyro_look_active`); a pad without touch sense aims always. Yaw is `values[1]`, pitch `values[0]`, roll is ignored; `GYRO_LOOK_PIXELS_PER_DEGREE` (20) times the gyro sensitivity. The Gyro setting stops only the aiming, so the diagnostics still show the sensor.
- `calibrate_gyro` learns the bias while the gyro is not aiming and the controller is still, subtracts it and treats a small rest as zero. Until the first still period the raw rate is used. The diagnostics show the raw rate, the bias and the corrected rate.

| Constant | Value | Meaning |
| --- | --- | --- |
| `GYRO_STILL_TOLERANCE` | 0.02 rad/s | Consecutive samples this close count as still |
| `GYRO_STILL_SAMPLES` | 90 | Still samples (frames) before the bias is taken |
| `GYRO_DEADZONE` | 0.01 rad/s | Corrected rate below this is rest |
| `GYRO_FULL_SCALE` | 35 rad/s | About 2000 degrees per second; a sample past it is a misread and reads as zero |

### Steam Input beside the game

Rule: in Game Mode Steam Input stays on for this controller even with the shortcut's per game setting disabled, so the launcher lets SDL open the real controller beside Steam's layer, and the gyro comes from Steam's layout.

- The play build's launcher (`tools/install_play_build.sh`) unsets `SDL_GAMECONTROLLER_IGNORE_DEVICES` and sets `SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=0`, so SDL opens the controller through HIDAPI while Steam's layer runs.
- Steam and SDL both set the controller's IMU mode with no arbitration (last writer wins), so SDL's gyro reads a report layout Steam left: a constant rotation that ignores motion. With `SteamVirtualGamepadInfo` set the game ignores SDL's gyro (`Gyro_Source` `Steam`) and takes Steam's mouse movement instead; the diagnostics say which.
- Steam's controller layout for the shortcut: gyro as mouse, active while the right pad or right stick is touched; the trackpads without mouse output, so they reach SDL alone.
- Steam Input for the desktop launch is turned off per shortcut: Properties, Controller, "Disable Steam Input" ([build.md](build.md) has the shortcut tool).

Telling what SDL opened:

- The log line `input: opened gamepad <id> "Steam Controller" vendor 28de product <id> path /dev/hidraw<n> touchpads 2` is the real controller. An evdev path (`/dev/input/event*`) with `touchpads 0` is Steam's virtual pad, as is `gamepad has no GYRO sensor`.
- The line before it (`steam_input_environment_text`) reads two variables of the launch: `SDL_GAMECONTROLLER_IGNORE_DEVICES` (Steam lists Valve controllers there, `0x28de/`) and `SteamVirtualGamepadInfo` (the path of Steam's `virtualgamepadinfo.txt`). Neither set logs "Steam Input is off for this launch (no ignore list, no virtual gamepad info)"; both set means Steam Input is on. Steam relabels its virtual pad as "Steam Controller" through that file, so the name alone proves nothing.
- The diagnostics Input page (F3) shows the backend, the gamepad, `touchpads 2`, touch sense and both sensors when SDL has the real controller.
- Observed on the couch: SDL input keeps arriving while the game's window is unfocused; the game does not check focus.

## Steam Deck

The Deck's built in controls take the couch's path (0076): the same launcher, the gyro from Steam's layout as mouse. The host SDL carries a "Steam Deck" mapping (vendor 28de, product 1205) whose `paddle1` to `paddle4` are the back grips, which the bindings treat as the Steam Controller's L4 R4 L5 R5. Untested on a Deck: which grip SDL names which paddle, and whether the Deck's SDL opens the controller at all (the `input: opened gamepad` line tells).

Layout to set for the shortcut on the Deck (Game Mode, controller settings, Edit Layout):

- Gyro as mouse while the right pad or right stick is touched.
- Trackpads without output, so they reach SDL.
- Back grips: nothing when SDL got the real controller (they arrive as paddles). If SDL got the virtual pad, bind them to the buttons of the same actions: L4 to A, R4 to B, L5 to Y, R5 to d-pad up.

## Android

Input on the phone is raylib's (0114). A Bluetooth or USB gamepad works at once with the raylib bindings; the Steam Controller features are SDL only.

- Touch is the pointer: raylib holds the left mouse button while a finger is down, and `read_raylib_mouse` takes the first touch's position, keeping the last one after the lift (`touch_pointer_position`), so a tap clicks where it lands.
- With the touch overlay off, a drag moves the mouse delta and turns the view as a mouse would. The overlay is on by default there and takes the touches in the world ([touch_overlay.md](touch_overlay.md)).
- Haptics play on the phone's vibrator (0122): each frame with a strength above 0 renews a 100 ms one shot at `vibration_amplitude` (1 to 255, 0.5 is 128), or the default amplitude on a vibrator without amplitude control; the first frame at 0 cancels it. A gamepad attached to the phone does not rumble, and the raylib backend plays no haptics outside Android.
- Text entry through the phone's IME: [ui.md](ui.md) (On-screen keyboard) and [android.md](android.md) (Keyboard).

## Bindings

Rule: every action a control triggers is a line in `data/bindings.sjson` (0025); the file's header documents the vocabulary.

- An entry names an action (the `Action` enum), a device (`gamepad`, `keyboard`, `mouse`, `trackpad`), a control, a context and an optional backend (`sdl3` or `raylib`).
- The context (`world`, `menu`, `both`) documents the layout and switches nothing in the input frame: which actions reach the world while a screen is open is `WORLD_ACTIONS`. The touch overlay's control lookup (`touch_control_for_action`) skips `menu` bindings.
- A configuration file may list `bindings` in the same shape; every action it lists loses all of its defaults (`effective_bindings`). The settings' Bindings tab shows the effective list read only (`binding_rows`).
- The glyphs show the effective bindings (0151, `glyph`): the first control bound to the hint's action on the active device that the backend reads (raylib skips the paddles, MISC buttons, GUIDE and TOUCHPAD, `raylib_reads_gamepad_control`), since the glyph bar has room for one. On the keyboard Back shows Pause's Esc, which steps back a screen too, and Sprint shows `Sprint_Hold`; each falls back to its own action's key when the other has none.
- One control carries a world and a menu meaning: A is Jump and Confirm, X Open_Inventory and Interact in the world and the context action in menus (0233). A jumps everywhere.
- Interact turns a power switch like a lever, in the block world and on the field, and takes a schematic crate's schematic. It opens no panel and launches nothing: a launch pad launches from its panel (0233). On the pod's hatch it does nothing (0231: the doors open and shut on their own, [content.md](content.md), Hatches). On the pod's chair Interact unbuckles after touchdown, then stands and sits; while seated it is the chair's whatever the aim, and the touch tap presses it (0223, `field_chair_takes_interact`). Strapped in or seated the look is free and the walk, Jump, Sneak, Mine, Place and the tools do nothing. Seated, not strapped, the camera toggle switches first and third person as on foot (0285).
- Open_Inventory means "open" (0194): pressed in the world while a machine with a panel is aimed in reach (`aims_at_panel`, read from the target the HUD shows: the block world's raycast, the predicted field player's frame cell), the press becomes `Open_Aimed` before the frame's input reaches the session or the UI (`route_open_inventory_press` in `update_frame_world`), so the simulation opens the panel and the inventory stays shut; anywhere else it opens the inventory and the simulation sees nothing. A press that is Interact's in the same frame (the gamepad's X, the touch tap) on a target that takes Interact (`entity_takes_interact`: a power switch, a full schematic crate) is Interact's alone: Open_Inventory leaves the frame, so the switch turns or the crate is taken and nothing opens (0233, `viewport_aimed_target`; not while the placement editor is anchored, which takes Interact). The keyboard's E and F are separate keys, so E opens a switch's panel (the pole panel with the network's name and the same toggle, also reached from any pole of the network). `Open_Aimed` has no binding of its own and rides in the input record like any action. Online the open lands a window later on whatever the player aims at then. With a screen open the press closes it as before ([ui.md](ui.md)).
- Place and Use_Item share L2 and the right mouse button; Use_Item acts while a usable item is selected (a schematic, the geologist's hammer, the magnetometer, a thumper charge; `resolve_use_item`), and Interact on a schematic crate takes and reads it in one press.
- Rotate_Building with no rotating item selected turns the targeted belt, splitter, inserter or drill (`entity_rotates`).
- The grips copy face buttons on purpose, so the thumbs stay on the sticks. R2 mines and L2 places as in Minecraft Bedrock's controller defaults. On the field Mine digs only with a shovel or a pickaxe selected and fells any tree with an axe; with the hand or any other item it digs nothing and fells only a small tree (0265, [content.md](content.md), Tools).

### Gamepad

| Input | In the world | In menus |
| --- | --- | --- |
| Left stick | Move. Click: Sprint | Focus navigation |
| Right stick | Look | Scroll lists. Click: `Menu_Drop` (drop the held or focused stack) |
| Gyro | Fine aim while the right stick or pad is touched | Off |
| Right trackpad | Look as a mouse surface. Click: Interact (turns a switch, takes a crate's schematic; nothing on a launch pad) | Pointer. Click: a pointer click, or Confirm while the pointer is hidden ([ui.md](ui.md)) |
| Left trackpad | Hotbar radial: touch shows it, slide to a slot, release selects, the centre (`RADIAL_CENTER_RADIUS` 0.15) cancels; the right stick does not turn the view while it is open | Letter wheel in the recipe, technology and statistics lists |
| R2 | Mine | Confirm; `Menu_Quick_Move` on a slot |
| L2 | Place, Use_Item | `Menu_Secondary` (split) |
| A | Jump | Confirm |
| B | Sneak | Back |
| X | Open_Inventory and Interact, one action per aimed target: a power switch turns, a full schematic crate is taken, the pod's chair unbuckles after touchdown, then stands and sits (seated, whatever the aim), a machine with a panel (a launch pad included) opens it, else the inventory opens (an empty crate included) | Context action (sort, craft five) |
| Y | Rotate_Building | Info panel |
| D-pad | Left, right: hotbar previous and next. Up: the tools radial held, Pipette tapped. Down: Drop_Stack. In the placement editor the four nudges | Focus navigation |
| L1, R1 | Hotbar previous and next | Tab previous and next |
| L4, R4 | Jump, Sneak | Confirm, Back |
| L5, R5 | Rotate_Building, the tools radial (Pipette) | Info panel, navigate up |
| View (`BACK`) | Open_Map | Open_Map |
| Menu (`START`) | Pause | Pause, which acts as Back over a screen |

The bindings name SDL's buttons, not the physical ones, and the game swaps nothing: `BACK` is Open_Map, `START` is Pause (`data/bindings.sjson`). SDL's driver may report View and Menu the other way round from the usual convention, so if Menu opens the map, the diagnostics Input page shows which physical button reads as `BACK`.

### Keyboard and mouse

`data/bindings.sjson` lists every key; WASD and the mouse's look are not bindings. Keys 1 to 8 select hotbar slots (9 and 0 are free); F3 to F9 are developer keys (F8 only in developer mode). F7 drops an iron plate on the targeted belt. In menus Backspace is Back, Enter Confirm, Q and E the tabs; Q also quick moves, and the inventory and machine panels take the quick move over the tab step, while E closes the inventory tab strip. Left Control held with a click quick moves (`Menu_Quick_Move_Modifier`). The statistics (N), the bottleneck overlay (O), the recipe browser (C) and the journal (J) have no direct gamepad button; the pause menu and the inventory tab strip reach them. Q and the middle mouse button hold the tools radial (Pipette tapped); the arrows nudge in the placement editor and navigate in menus.

### The placement editor

A machine wider, deeper or higher than `direct_placement_limit` ([content.md](content.md), Foundations; 2 by 2 by 3 shipped) is placed through the editor while it is on (0215, `ui_placement_editor.odin`). The editor is per local player, off at a session's start, never saved, hashed or sent. Its modes:

- **World, the tools radial held.** Hold Pipette's control (D-pad Up or R5, Q, the middle mouse button, the touch Tools button): the radial shows (Pipette at the top, Placement editor with its state at the bottom, `tools_radial` in `hud.odin`); the look input steers. A tap, released before `TOOLS_RADIAL_SHOW_SECONDS` (0.2 s) with nothing highlighted, is Pipette, which reaches the world as one press on the release (`tools_radial_world_frame`), never on the press; once the radial has shown, release on an entry selects it and release in the dead centre selects nothing. The right stick past 0.3 steers directly; otherwise the frame's look pixels (the mouse, the right trackpad, the gyro, the Tools button's own drag) gather into a steer clamped to 150 window pixels, so a short flick reaches an entry and the steer stays while the button is held. While it is open the world gets no Look. Not while the hotbar radial is open or the editor is anchored.
- **World, the editor on, a large machine held.** Every control keeps its meaning; the ghost is low walls round the footprint centred on the aimed cell with an arrow for the front ([presentation.md](presentation.md), The field session), white, red where the placement would be refused, and Place (with Use_Item, which shares L2) anchors instead of placing. Place on a red outline is refused with the reason toasted.
- **The editor mode** (after the anchor): the ghost stays anchored as the machine's model while the player walks round it.

| Control | In the editor |
| --- | --- |
| Left stick, right stick, gyro, trackpads | Move, Look, as in the world (walk round the ghost) |
| A | Jump |
| B | Sneak |
| Left stick click | Sprint |
| D-pad Up, Down | Nudge the ghost one cell away from and towards the player, along the frame axis nearest the player's facing |
| D-pad Left, Right | Nudge the ghost one cell across |
| Y (Rotate_Building), L5 | Rotate the ghost 90 degrees about its centre |
| L2 (Place) | Commit |
| R2 (Mine) | Cancel: the world's build and remove pair becomes the editor's yes and no |
| L1, R1 | Hotbar previous and next, which cancels the editor (the held machine changes) |
| X (Open_Inventory) | Opens the inventory as in the world; the ghost stays anchored and the editor resumes when the screen closes |
| Menu (Pause) | The pause menu, with a `Cancel placement` row while the editor runs |
| View (Open_Map) | The map, as in the world |
| Keyboard and mouse | Arrows nudge, R rotates, right click commits, left click cancels, Escape opens the pause menu with its row |
| Touch | The HUD's editor buttons: the four nudges, commit and cancel, with Rotate in the row ([touch_overlay.md](touch_overlay.md)); Default's B is Sneak |

The nudge actions (`Placement_Nudge_Away`, `_Towards`, `_Left`, `_Right`, on the D-pad and the arrows) never reach the simulation: the world frame always drops them (`placement_editor_world_frame`), so outside the mode the D-pad keeps its world meanings. In the mode the world frame also drops Place, Use_Item, Mine, Rotate_Building, Pipette, Drop_Stack and Interact (so X there is Open_Inventory alone), and Hotbar_Previous or Hotbar_Next only while the D-pad's Left or Right nudge is held in that frame, so L1, R1, the wheel, `[`, `]` and the number keys still change the slot and cancel. Away is the frame's horizontal axis nearest the player's heading, Left and Right the other one signed by the player's right; the frame's up is never a nudge axis. On bare ground a nudge re-stands the machine's new frame on the ground under the moved centre (no ground in reach leaves it and toasts Too steep). Every change re-runs the placement's refusal and re-tints the ghost. Commit on a white ghost queues one `Machine_Placement_Command` ([architecture.md](architecture.md), Placement on frames); on a red one it is refused with a toast. After a commit Place, and after a cancel Mine, stay hidden from the world until released (`Placement_Editor.guard`), so a held R2 after Cancel does not start a pick up. Changing the held slot or losing the held machine cancels too.

## Hold or toggle

The Accessibility tab's Sneak and Sprint rows (`settings.sneak_hold`, `settings.sprint_hold`, `hold` or `toggle`, 0074) choose how the two actions act.

| Action | Default | Hold | Toggle |
| --- | --- | --- | --- |
| Sneak | Hold | Sneaks while held | A press starts, the next stops; it lasts through open screens |
| Sprint | Toggle | Sprints while held and moving | A press while moving sprints until movement stops or the next press |

On touch, Default's B (0227) presses Sneak's `EAST`: in Hold it sneaks while touched and a double tap keeps it down until the next tap, in Toggle a tap toggles ([touch_overlay.md](touch_overlay.md), Hotbar and HUD buttons).

The tools radial (0215) is hold only; the two settings do not touch it.

`Sprint_Hold` (Left Shift) sprints while held whatever the Sprint setting. `update_sneaking` and `update_sprinting` read the choice from the frame. The player's `Player.sneaking` is the truth, and the rest of the tick sees Sneak pressed exactly while it is set (`with_sneaking`), so a toggled sneak while flying keeps descending until toggled off. `update_sneaking` and `with_sneaking` run in the field tick and its prediction too (0218), where Sneak on foot crouches ([architecture.md](architecture.md), The player on the field); the block world's sneak (the slow walk with the edge check) is unchanged.

## Fly mode and no clip

- In developer mode a second Jump press within `JUMP_DOUBLE_TAP_TICKS` (18 ticks, 300 ms) toggles fly mode (0112); outside it a double tap is two jumps. A tick after any blocked frame closes the window (`Input_Frame.world_blocked`), so a Jump before the pause menu and one after it are no double tap.
- F6 and the Developer screen toggle flying too. Flight is swept against blocks like walking; no clip (F9, the Developer screen, `noclip on`) lets flight pass through blocks. Walking ignores no clip, and neither is saved.
- Every change logs `player: fly mode on at tick N by <cause>` (or no clip), so an unexpected toggle shows in the log or logcat.
- On the terrain field (0170) the same toggles fly the field player in the planet's frame: the move along the heading and its right on the tangent plane, Jump and Sneak along the planet's up, swept against the field unless no clip is on ([architecture.md](architecture.md), The player on the field). The planet preview's walk mode is a developer tool, so its double tap always flies; there the log line names no cause.
- The planet preview (`--planet-preview`) switches between its free camera and the field player with G (`PLANET_PREVIEW_WALK_KEY`), a raw key of the preview rather than a binding; V toggles the third person camera there, and Sprint and Sprint_Hold both sprint while held ([build.md](build.md), Command line).

## Split screen

Up to four local players share the window, each in a viewport (`viewport.odin`, work item 0178; the frame side in [architecture.md](architecture.md), Frame and tick).

- Devices: the first viewport reads the keyboard, the mouse and the touch overlay, and takes the first gamepad no viewport owns as soon as it has none, so one pad plays single player as before. Every other viewport reads its own gamepad, by SDL id, and nothing else. The raylib backend tells no pads apart, so it plays one viewport only.
- Joining: Start (the Pause action) on a gamepad no viewport owns adds a viewport and a local player while a world is played (`pad_claim`, `add_viewport`), through the add player path of a join: the first save entry no member holds, else a new player at the start. The held Start is no fresh press in the new viewport, so its pause menu does not open.
- A disconnected pad leaves its viewport waiting with its player in the world and a notice ("Controller lost: press Start"); Start on any free pad takes the waiting viewport again (SDL gives a pad plugged in again a new id). The waiting guests come first: while one waits, a keyboard first viewport without a pad takes no free pad, and Start gives the pad to the waiting guest, so a replugged guest pad is never taken silently. A guest viewport leaves through its pause menu's Leave split screen; its player stays in the world and the next join takes that entry.
- The keyboard and the mouse belong to the first viewport (no setting moves them). Since that viewport takes the first free pad too, the keyboard and one pad are one player, not two; a second player needs a second pad. In split screen the mouse's position is taken in that viewport's own pixels, and the touch overlay is off: a phone is one remote player.
- Bindings and the input frame are as above, per viewport; each viewport accumulates its own tick input (`Tick_Input_Accumulator`) and rumbles its own pad.

## Not built yet

- Generic gamepads: the action layer takes any pad, but the trackpad only actions (hotbar radial, letter wheel) need stick and button equivalents first.
- Selection assist: the reticle snaps to the nearest entity, the bumpers cycle overlapping candidates, holding Y names everything under it ([inspiration.md](inspiration.md) has the Factorio Switch reasoning).
- Distribute gesture: L2 held while sweeping the reticle across machines spreads the held stack evenly (the Even Distribution mod). The menu version, A held across slots, exists ([ui.md](ui.md), Item slots).
- Close all on View in menus.
