# 0352: Terrain multi-draw and a depth pre-pass

Status: todo (2026-11-11)

All terrain nodes share one material and go out as 100 to 200 draws, again for the shadow pass, and the field's fragment shader reads up to 24 atlas and 16 shadow samples a pixel (`work/performance_research_0340.md`, 2.6). Whether either costs here is unknown until 0342's first table: the design starts from it and says so if the table shows neither.

## Goal

Fewer draw submissions for the terrain and no shaded pixel that ends up covered, where the table shows they cost.

## Controls

None.

## Change

- Terrain nodes in a few large buffers drawn by one multi-draw, the present path kept where the phone's GLES 3.0 or Winlator lack it.
- A depth only pass first and the colour pass on an equal depth test, the tree cards' `discard` with it.

## Verify

- The checks and the suite.
- 0342's table: draw submission on the CPU and the terrain's GPU time in every view, before and after.
- Captures before and after, sent to the user.
