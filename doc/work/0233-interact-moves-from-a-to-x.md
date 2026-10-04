# 0233: Interact moves from A to X, A jumps alone

Status: designing (2026-10-04, from the user: "Do we still have 'A to interact' still left bound for anything? In that case i want it moved to X. A shall be solely for jumping"; today A and the L4 paddle carry Jump and Interact, Interact winning on a power switch, a launch pad and a schematic crate (`without_interact_jump`, `without_field_interact_jump`); after 0231, which takes the hatch off Interact)

## Goal

On the gamepad A jumps and nothing else in the world. Interact lives on X beside Open_Inventory, and what X does is decided by the aimed thing, one action per target, so a press never does two things and never jumps.

## Controls

Control design (main agent, 2026-10-04). The world layer only; menus are unchanged (A confirms, X is the context action, as on every pad).

- **Bindings** (`data/bindings.sjson`): Interact leaves `SOUTH` and `LEFT_PADDLE1` and is bound to `WEST` in the world context; `MISC2` (the right trackpad's click) keeps Interact, since it carries nothing else; Jump keeps `SOUTH` and `LEFT_PADDLE1`; Open_Inventory keeps `WEST` in both contexts; Confirm keeps `SOUTH` in the menu context. Keyboard and mouse are unchanged (Space jumps, F interacts, E opens).
- **X in the world, one action per aimed target**: a power switch turns (Interact, the lever; its panel is the pole panel with the network's name and the same toggle, reached from any pole of the network or with E on the keyboard); a schematic crate is taken and read (Interact); a launch pad opens its panel (Open, where Assemble and Launch are; Interact's direct launch from the pad goes, so a ready rocket can still be inspected); any other machine with a panel opens it (Open, as today); nothing aimed, or a thing with neither, opens the inventory (as today). The design stage picks the seam: either the presentation's routing (`route_open_inventory_press`, which turns Open_Inventory into Open_Aimed on a panel) leaves the press as Interact on a switch and a crate, or the simulation's `resolve_interact` and `interact_on_field` check the lever and the crate before Open_Aimed; the outcome per target above is what the tests assert.
- **A jumps always**: `without_interact_jump` and `without_field_interact_jump` go, since Jump no longer shares a control with Interact; a press on a switch or a pad jumps as anywhere.
- **What every existing control still does**: B Sneak, Y Rotate_Building, the D-pad, the bumpers, the triggers (R2 Mine, L2 Place and Use_Item), the trackpads, the paddles L5 and R5, View and Menu: unchanged. The right trackpad's click stays Interact (a lever turn or a crate take with the pad, as today); on a launch pad it does nothing, since the launch is the panel's.
- **Touch**: the tap on a switch or a crate presses `WEST` as on any panelled machine (today `tap_interact_control` presses `SOUTH` there); the design stage says whether the look element's `tap_interact_control` key stays for user layouts (set to `WEST` in Default) or goes with its loader line and the tap always presses `tap_open_control` where the target takes Interact or has a panel.
- **HUD**: the Interact glyph follows the binding and shows X; a switch shows Turn alone (today Turn beside Open, two hints on what are now one control), a pad Open alone, a crate Take alone; the inventory hint shows X as today.
- **The placement editor**: A Jump, unchanged; its table in `doc/input.md` already says so.

## Change

- `data/bindings.sjson` and its header comment; `src/player.odin` (`resolve_interact`, `without_interact_jump`, `entity_answers_interact`, `entity_takes_interact`), `src/simulation_field.odin` (`interact_on_field`, `without_field_interact_jump`), `src/input_actions.odin` (`route_open_inventory_press`) as the design stage decides; `src/hud.odin` (the switch's double hint); the touch tap routing (`tap_control`, `touch_overlay.odin`) and `data/touch_overlay.sjson`'s look element.
- Docs: `doc/input.md` (the bindings table rows A, X and L4, the Interact paragraphs, the editor table's A row), `doc/touch_overlay.md` (the tap line), `doc/ui.md` (line 59's tap routing), `doc/hud.md` (the hints), `doc/content.md` (the switch and the pad lines), `doc/log/2026-10-04.md`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the shipped bindings give `SOUTH` Jump and Confirm only, `WEST` Open_Inventory and Interact in the world, `LEFT_PADDLE1` Jump only, `MISC2` Interact; aimed at a power switch an X press turns it and opens no panel, in the block world and on the field; aimed at a launch pad with a rocket ready an X press opens the panel and launches nothing; aimed at a schematic crate an X press takes it; an A press aimed at a switch jumps and turns nothing; the glyph bar on a switch shows Turn once; the touch tap on a switch presses `WEST`; the existing Open_Aimed tests pass unchanged.
- The couch: turn a switch with X, open a furnace with X, jump with A in front of a switch; the phone: tap a switch.
