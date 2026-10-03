# 0107 Joystick lines in the log

Status: implemented
Milestone: M11

## Goal

On the phone (Winlator, 2026-09-29) the on-screen Virtual Gamepad does nothing in the game while its mouse emulation works. Winlator's Wine fork presents the overlay as a HID gamepad from its own bus driver (`dlls/winebus.sys/bus_winlator.c` in `brunodev85/wine-10.10-custom`, copy under `tmp/winlator-app/`): manufacturer "Winlator", vendor and product of an Xbox 360 or Xbox One pad from `gamepad_models.json`, flagged as an XInput gamepad when the shortcut's DInput mapper type is XInput (ten buttons, axes X, Y, RX, RY, Z, RZ). The game's SDL3 backend (`src/input_sdl3.odin`) opens a gamepad only on `GAMEPAD_ADDED`, so a joystick SDL sees but does not take for a gamepad (no mapping for its GUID) leaves no trace in the log, and neither does one SDL never sees. The log must tell those apart.

## Change

- In `poll_sdl3_events`, log `JOYSTICK_ADDED` and `JOYSTICK_REMOVED` too: one line `input: joystick <id> "<name>" vendor <vid> product <pid> guid <guid> <gamepad|no gamepad mapping>` from `sdl.GetJoystickNameForID`, `sdl.GetJoystickVendorForID`, `sdl.GetJoystickProductForID`, `sdl.GetJoystickGUIDForID` with `sdl.GUIDToString`, and `sdl.IsGamepad(id)`; and `input: joystick <id> removed`. The existing gamepad lines stay. Format the line in a pure procedure with a test (`src/input_sdl3_test.odin` or the existing input test file) that passes the strings and numbers in.
- After `init_sdl3_input` succeeds, log how many joysticks SDL sees at start (`sdl.GetJoysticks`), one line, so an empty list on the phone is visible even before any event.
- Documentation in the same commit: a sentence in the input paragraph of `doc/architecture.md`, and an entry in `doc/log/2026-09-29.md` (tags `#windows #input #winlator`) with the Winlator facts above and that the shortcut's Controls Profile and DInput Mapper Type settings pick the overlay and its device type at start.

## Verify

- `./build.sh check`, `./build.sh check-windows`, `./build.sh test`.
- User: the couch log shows the Steam Controller's joystick line before its gamepad line; the phone log shows what SDL sees when the overlay is on.

## Implemented

2026-09-29: `./build.sh check`, `./build.sh check-windows` and `./build.sh test` (1054 tests, including `test_sdl3_joystick_line_names_the_device_and_its_mapping`) pass. The couch and phone log checks are left to the user.
