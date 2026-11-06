# 0304: The entry's flames outside the pod

Status: todo (2026-11-06)

Milestone: the entry's look (0273, 0286, 0288, 0290), 0303 folded in. The user (2026-11-06), on a Kerbal Space Program reentry seen from outside (`work/reference/0303/ksp_reentry_outside.jpg`): the flames are straight and long, and they do not lick the cone's slanted walls but run straight aft from the heat shield's widest rim; doing the real flames on the outside might straighten out the visuals, and is interesting for multiplayer. Today the plasma (0288) and the flakes (0290) are drawn only on the portholes, so the pod falls without a flame from any other view, and the flakes do not read from the chair (0303).

## Goal

During the fall the plasma is drawn on the pod in the world: the glowing shield and a wake streaming straight aft from its rim at the base's width, long, fading with distance, clear of the cone. Every viewer sees the same flames, from the chair through the portholes as from the third person camera or another pod, and the flakes shed from the rim into the wake read from the chair and from outside.

## Controls

None.

## Change

- The wake as geometry on the pod in its model frame: its shape from the rim, its length, the flow and the fire flicker of 0286 and 0288 carried over, the shield's glow; how the porthole sees it (beside the cone at the rim's offset, through the glass and the soot) and how it reads against the sky and the ground.
- The window sheath of 0288 goes where the wake covers it; the soot on the outer pane stays.
- The flakes of 0290 drawn outside, sized, counted and lit to read from the chair and from outside, their streaks long and straight. 0303's measurements of the footage against our captures size them (the log of this item).
- Docs: `doc/presentation.md` (The arrival); the log.

## Verify

- The checks and the suite.
- Captures at the peak from the chair's porthole and from the third person camera beside the pod, the flakes counted by the capture difference of 0290; sent to the user beside the reference picture and the footage.
