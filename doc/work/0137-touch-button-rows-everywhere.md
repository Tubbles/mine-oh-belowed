# 0137: Button rows on every screen for touch, taps select only

Status: todo

## Goal

Asked on 2026-09-30: "The back button is labeled 'back' but in almost all screens it does nothing, it doesnt back out of the screen. Also there are still a lot of screens that shows glyphs. And tapping in research screen shouldn't craft the item, instead it should select it so we can read about it. Similarly as inventory, tapping items just moves the selection, not commits to anything. Do the same for the research screen as well (if applicable)." And, 2026-09-30 later: "Tapping outside pause menu doesnt resume the game, make sure all menus and screens can be closed by tapping outside them."

## What the code says

- The overlay's Back pill presses the gamepad's `BACK` control (`data/touch_overlay.sjson`), and `data/bindings.sjson` binds `BACK` to `Open_Map` in both contexts, never to the `Back` action, which is `EAST` (B) in menus. So the pill opens or closes the map at best and closes no other screen. The pill leaves with 0134; until then it is what it is, and the Back button of this item's rows is what closes screens on touch.
- The 0124 outside tap closes only the screens that do not pause the simulation (`ui_core.odin`, the outside tap rule names inventory, recipes, technologies, machine, journal, power, statistics, map); the pause menu, settings, developer, the editors, the title's screens and the confirm dialog keep their own Back, so a tap beside the pause menu does nothing.
- 0125 replaced the glyph bar with a button row on the inventory screen and the machine panels only. Every other screen (`ui_glyph_bar` callers: the pause menu, settings, developer, the texture editor, the recipe browser, technologies, journal, power, statistics, map, the title screens, the touch layout editor, the HUD's world hints) still draws glyphs on touch.
- The recipe browser queues a craft on Confirm (A, a tap) and the technology screen starts research on Confirm, so a tap commits instead of selecting.

## Change

- On the touch pointer (`Ui_Input.pointer_is_touch`) every screen's glyph bar becomes a row of buttons through 0125's `ui_button_bar`: Back always, then the screen's actions that the glyphs named (the pause menu and the title screens have Back only or nothing; settings: Back; developer: Back; the texture editor: its own Reset, Save, Back are buttons already, the row is Back; journal, power, statistics, map: Back and the screen's actions; the touch layout editor: its actions are buttons already). One pure procedure per screen maps its state to the row's buttons, like `slot_button_row` in 0125, with a test each. The HUD's world hints draw nothing on touch (the gestures are the hints).
- The recipe browser on touch: a tap on a recipe selects it (focus and the description, no craft); the row has Craft and Craft five (what A and X do) beside Back, acting on the selected recipe, and Cancel newest (L2). The technology screen on touch: a tap selects a technology, the row has Research (what A does) beside Back. The gamepad and the keyboard keep their glyphs and their Confirm. The inserter and splitter filter slots gain a Clear filter button in the machine panel's row on touch (0125 left the filter unclearable by touch), and the inventory row gains Drop (0125 left it out).
- The outside tap (0124) closes every screen that has a panel: the pause menu resumes, settings and developer return to the pause menu, the texture editor and the confirm dialog go back, new world and load world return to the title. Same rules as 0124: press and release outside every panel and widget, within the slop, nothing held, not while the on-screen keyboard is open (with the system keyboard, 0133, the outside tap ends the entry first and the next one closes the screen). The touch layout editor's canvas is the whole screen, so it keeps its buttons; the title screen has nothing to close.
- With every screen closable from its row, the 0124 outside tap and 0134's HUD buttons complete the touch navigation; the map's Back and the Open_Map binding of the BACK control are unchanged.
- Docs: `doc/ui.md` (the Touch button row section covers every screen; the recipe and technology taps), `doc/input.md` (the BACK finding), `doc/log/2026-09-30.md`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: on touch no screen draws a glyph bar and every screen's row has Back (walk the screens as the UI bounds audit does, with `pointer_is_touch`); Back on each row pops the screen; A tap outside the pause menu resumes, outside settings returns to the pause menu, outside new world returns to the title, outside the confirm dialog cancels; a tap on a recipe row selects and queues nothing, the Craft button queues one; a tap on a technology selects and starts nothing, the Research button starts it; Clear filter clears an inserter's filter; Drop drops the focused stack; the audit covers the rows.
- The user, on the phone: close every screen with its Back button and again by tapping outside it, the pause menu included; read a recipe and a technology by tapping them, craft and research with the buttons.
