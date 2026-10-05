# 0281: The erase mode

Status: todo (2026-10-05)

## Goal

A mode for tearing down, Techtonica's deconstruct mode (user, 2026-10-05): while it is on, Mine picks up the aimed machine, belt, pole or foundation and nothing else (no digging, no felling), the aimed thing is outlined in the danger colour with its name and "Pick up" in the glyph bar, and Place does nothing; one press of its control enters it and one leaves it. The direct pick up with Mine on a frame cell (0195) goes with it, so a held R2 at a machine never tears it down by accident.

## Controls

- The toggle: L1 in the world, free after 0280; a press enters, a press leaves. The HUD shows a banner over the toolbars while it is on and the glyph bar reads L1 "Done". The tools radial of 0215 lists it too, for the touch overlay and the keyboard.
- Inside: R2 picks up the aimed thing, L2 does nothing, Rotate does nothing, the toolbars step as usual (the held item is irrelevant while it is on).
- Open (user): Techtonica toggles it on the trigger that places; here L2 is Place, and a second meaning with the hand selected would break the rule of 2026-10-03, so L1 or the radial.

## Change

- `Player.erase_mode` per local player, never saved, hashed or sent (as the placement editor); the world frame drops Place, Use_Item, Rotate_Building and the digs while it is on; the pick up stays 0195's command.
- The HUD banner, the outline, the glyph bar, the UI audit case.
- Docs: `doc/input.md` (a mode table like the placement editor's), `doc/hud.md`, `doc/content.md` (Machines on frames).

## Verify

- Tests: Mine in the mode on a machine picks it up, on ground digs nothing, on a tree fells nothing; Place does nothing; leaving restores every control.
- The UI audit's banner case at every size.
- The couch.
