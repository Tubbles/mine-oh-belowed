# 0329: The broadleaf tree model

Status: todo (2026-11-07)

0310 places five species in its forests, each a stand-in on `pine_tree` with its own tint, yield and scale range until its model comes from the sealed lab (CLAUDE.md, Model items). The broadleaf is 38 percent of a forest's trees, the commonest after the pine, and today a tinted pine. One species at a time, in the order 0329 to 0333.

## Goal

A broadleaf that reads as one from the forest floor and from 120 m, varied enough by its scale and tint that a stand of it does not repeat, in at most 600 triangles (0310's near draw holds up to 1024 trees).

## Controls

None.

## Change

- A reference sheet of the broadleaf first, the user's call on its look.
- The brief from `tools/model_lab/brief_template.md` and the lab (`python3 tools/model_lab/model_lab.py build`): the user's words, the sheet, the 600 triangle cap, the renderer's limits, 0310's scale range for the species and its far card (baked from the model).
- Rounds: the modeller's previews, the game's previews and the hero image to the user, notes back to the same modeller until the user accepts.
- The integration by an implementer: the species' record names the model, the OBJ regenerated and compared byte for byte with the lab's, the far card baked again, the tests and docs following.

## Verify

- The workbench's check and the suite.
- A forest interior and a stand from 120 m with the model, sent to the user.
