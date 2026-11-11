# 0372: A blue slab under the view when looking down

Status: todo (2026-11-11)

0342's check captures of the factory view (2026-11-11, `--dev --input=none`, fly on, the look 33 degrees down, the wooden foundation held) show a flat blue trapezoid across the bottom fifth of the picture, behind the hotbar, in one viewport and in both of two. It keeps its place on the screen in every viewport, so it moves with the camera. The spring and the other views, looking level with fly off, do not show it. What it is has not been read in the code: the player's own body seen from its eye is the main agent's guess, and the implementer's reading (the hotbar) does not fit, since the hotbar's slots are drawn over it.

## Goal

Looking down shows the ground, or a body that reads as one.

## Controls

None.

## Change

- Find what draws it (the player's body in first person, a held item's model, fly mode's own draw) and with which pitch and mode it appears.
- Hide what the eye is inside of, or draw it so it reads.

## Verify

- The checks and the suite.
- Captures looking down at 33 and at 80 degrees, on foot and flying, in one and two viewports, sent to the user.
