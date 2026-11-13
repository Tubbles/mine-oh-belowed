# 0384: The cable's look

Status: implementing (2026-11-13)

Step 3 of 0368's specification (`done/0368-cables-junction-boxes-and-the-poles-removal.md`, Steps and "The draw", step 3), split off at its approval. 0368 draws a cable as a line along its sag.

## Goal

A cable reads as a cable near the eye and costs little far from it.

## Controls

None.

## Change

- As 0368's specification, step 3: instanced boxes along the sag within 32 m, the `cables` instance buffer, lines beyond, and the frame profile's factory view with cables. Presentation only.
- After 0368. Independent of 0383.

## Verify

- The checks and the suite.
- Captures of a hand run factory near and at the haze, before and after, sent to the user.
- In the night window: the factory view's row with cables.
