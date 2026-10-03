# 0194: Open a machine with the inventory binding

Status: implemented (user, 2026-10-03: "we dont need a separate keybinding for opening a machine, we could just reuse the 'open inventory' keybinding, so it opens the normal inventory view when not pointing at any machine, and opening a machine's panel when pointing at a machine and standing close enough to it")

## Goal

One binding opens things: Open_Inventory (E, gamepad West, the touch overlay's inventory button) opens the aimed machine's panel when a machine with a panel is in reach, and the inventory otherwise. Today Interact (F, gamepad South shared with Jump) opens the panel on the field (`interact_on_field`, `simulation_field.odin`) and in the block world (`resolve_interact`, `player_interaction.odin`), and Open_Inventory always opens the inventory.

## Change

- The decision is made once, on the press, on the presentation side from what the user sees aimed (the predicted player's target, 0182): a panel machine in reach turns the press into the simulation's open action (the input frame's bit that `interact_on_field` and `resolve_interact` read for the panel, renamed if Interact no longer carries it) and the inventory screen does not open; otherwise the inventory opens and the simulation gets nothing. Online the open lands a window later on whatever is aimed then.
- Interact keeps what is not a panel: the switch toggle and the launch (`Toggled_Switch`, `Launch_Requested`), and still suppresses the jump on the field when aimed at one of those. It no longer opens panels on either world.
- The HUD's hint beside a machine shows the inventory glyph with "Open" (`hud.odin`, the `hint_open` line), the switch keeps the Interact glyph. The touch overlay needs no new button. `doc/input.md` (the actions), `doc/hud.md`, `doc/touch_overlay.md` if it lists the hints, `doc/architecture.md` (the field player's interaction) updated; the bindings audit test, if one lists the world actions, updated.

## Controls (the design pass, main agent, 2026-10-03)

- Mode: the world. Open_Inventory (keyboard E, gamepad West, the HUD's backpack touch button) means "open": a machine with a panel aimed within reach opens its panel, anything else opens the inventory. One control whose meaning follows the aim the HUD shows; no modifier, no layer. The hint beside such a machine shows the Inventory glyph with "Open".
- Interact (keyboard F, gamepad South shared with Jump) keeps the switch toggle and the launch only; its jump suppression on the field applies only when one of those is aimed, so South jumps everywhere else as before. Nothing else is bound or rebound.
- Screens: Open_Inventory with a screen open still closes it (the existing rule); the panel's own Back closes a machine.
- Touch: the backpack HUD button presses Open_Inventory and so opens the machine at the view's centre. A tap on a machine with a panel presses the same gamepad control (West, Open_Inventory) with the tap's aim, so the press is routed like any other and opens that machine (added 2026-10-03 after the implementation showed a tap on a furnace falling through to Place); a tap on a switch, a launch pad or a crate still presses Interact, any other tap Place. No touch code path of its own: the tap presses a gamepad control, as the overlay's rule says.

## Verify

- The build and check commands of 0168.
- Tests: Open_Inventory aimed at a furnace in reach raises `Open_Machine` and opens no inventory screen; aimed at the ground it opens the inventory and the simulation sees no open; Interact at a furnace opens nothing, at a switch toggles; the UI audit case of the hint beside a machine draws the inventory glyph.
- The couch: E on a furnace opens it, E on the ground opens the inventory, same with the gamepad.
