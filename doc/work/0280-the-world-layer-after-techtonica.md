# 0280: The world layer after Techtonica

Status: todo (2026-10-05)

## Goal

The world's buttons after Techtonica's (user, 2026-10-05, [inspiration.md](../inspiration.md), Techtonica's controls and screens): the d-pad alone steps the toolbars, the bumpers no longer step the hotbar; B hides the toolbars and sheathes the held item (the ghost goes, Place and Use_Item do nothing) until B again or a toolbar step; A interacts and X jumps; the left stick's click keeps sprinting. On 0278.

## Controls

The world layer, gamepad. Every line is a proposal until the user approves the item.

- D-pad Left, Right: the previous and the next slot of the active toolbar (as now). Up, Down: swap the active toolbar row (0278).
- The tools radial leaves D-pad Up and stays on R5, the keyboard's Q and the middle button, the touch Tools button. Open (user): a pad without paddles then has no tools radial, so it needs a second home, R1 held is free once the bumpers no longer step the hotbar.
- Drop_Stack leaves D-pad Down: a drop happens in the crafting view (the right stick's click) and by the touch long press. Open (user): whether a world drop is still wanted and where.
- L1, R1: free in the world. L1 is 0281's erase mode toggle if the user takes it.
- B: sheathe and toggle the toolbars. Sneak moves to the right stick's click (free in the world) and keeps R4; the hold or toggle setting applies as before, the placement editor's table follows.
- A: Interact (the switch, the crate, the chair). X: Jump, with the developer double tap fly toggle. This swaps the decision of 0233 (A jumps everywhere, X opens and interacts). Open (user): the note gives X both as the crafting view's button and as Jump, so which is it in Techtonica, and which of X and Y takes the crafting view here.
- Left stick click: Sprint, as now.
- The touch overlay follows (0115, 0134): the B button becomes the sheathe, the jump tap stays. The glyph bar reads the bindings.

## Change

- `data/bindings.sjson`, `WORLD_ACTIONS`, the placement editor's table, the touch overlay's layouts, the fly double tap on the new Jump.
- Docs: `doc/input.md` (Gamepad, the world column, The placement editor), `doc/touch_overlay.md`, `doc/hud.md`, `DESIGN.md` (The player).

## Verify

- Tests: the effective bindings carry no control with two world meanings in one context; the sheathe hides the ghost and blocks Place; a toolbar step unsheathes.
- The touch overlay's audit, the editor's table.
- The couch.
