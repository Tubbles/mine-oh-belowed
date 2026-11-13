# 0387: The junction box model

Status: todo (2026-11-13)

0368 (`done/0368-cables-junction-boxes-and-the-poles-removal.md`) draws the junction box as a plain inset box and lays every cable onto the middle of a face, a little off the drawn box. Its model comes from the sealed lab (CLAUDE.md, Model items). Before 0388, which follows its look.

## Goal

A junction box that reads as the place cables meet, from the hand and from 60 m, with a socket on each of its four port faces where a cable visibly ends.

## Controls

None.

## Change

- A reference sheet first, the user's call on its look (The Last Caretaker leads the game's look since 2026-11-11).
- The brief from `tools/model_lab/brief_template.md` and the lab (`python3 tools/model_lab/model_lab.py build`): the user's words, the sheet, the 1 by 1 by 1 footprint, the four port faces and their centres, the renderer's limits, the sanity caps.
- Rounds: the modeller's previews, the game's previews with cables on its ports and the hero image to the user, notes back to the same modeller until the user accepts.
- The integration by an implementer: the record names the model, the OBJ regenerated and compared byte for byte with the lab's, the cable's end points meeting the sockets, the tests and docs following.

## Verify

- The workbench's check and the suite.
- A hand-run factory with the model at noon and at dusk, from 5 m and 20 m, sent to the user.
