# 0343: A view distance setting

Status: todo (2026-11-11)

The field draws its terrain and its trees to 1024 m, fixed in the code. The user (2026-11-11), asked whether the view may shrink for 60 frames a second: "yes let's make it into a setting if it isn't already, and I can play around with it and say if I think its performant enough. 512 m can be the threshold for 60 fps for now".

## Goal

The player chooses how far the world is drawn, and the 60 frames a second bar is judged at 512 m.

## Controls

No world control changes. The Settings screen gains one entry, View distance, in its graphics group, stepped left and right as the screen's other stepped entries are (focus navigation and the pointer): 256 m, 512 m, 768 m and 1024 m, shipped at 1024 m until 0342's table says what the couch holds.

## Change

- One setting that bounds what the field draws: the terrain's levels of detail, the trees and their cards, the cover, in every viewport, applied without a restart.
- Presentation only: the simulated and streamed set that the lockstep depends on is not the setting's, so two players with different view distances stay in step.
- What is streamed and meshed only for the view shrinks with it, so a shorter view also costs less to fill.
- The command socket sets it, so 0342's views run at 512 m and 1024 m.
- Docs: `doc/presentation.md` (the level of detail, the trees), the settings' doc.

## Verify

- The checks and the suite, with a test that a session's state hash is the same at two view distances.
- Captures of the same view at 512 m and 1024 m, sent to the user.
