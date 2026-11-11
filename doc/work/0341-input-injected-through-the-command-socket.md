# 0341: Input injected through the command socket

Status: todo (2026-11-11)

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
