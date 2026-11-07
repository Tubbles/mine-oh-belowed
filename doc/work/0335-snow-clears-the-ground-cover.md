# 0335: Snow clears the ground cover

Status: todo (2026-11-07)

From 0311's landing captures: at the cold spot (81.4358 N, 159.9575 E, 0 °C, 70 % moisture) the terrain draws the ground white with snow, while grass tufts stand all over it (`test_the_cover_follows_the_climate` logs grass at 2.4 a square metre there). The user (2026-11-07): "Grass doesn't grow through snow no, if its not very freshly fallen and just a little amount. And I mean very freshly, like within a day, and at most 1 cm or something". The generated snow is settled snow, so no plant shows through it.

The grass kind already grows on no snow (`surfaces.snow = 0` in `data/planets.sjson`), so the cover's snow share (`cover_ground_shares`, from the look's weights) reads less snow than `field.fs` draws at that place.

## Goal

No grass, flowers or ferns on ground the terrain draws as snow, at any climate and slope; where snow thins out at its edge, the plants thin out with it.

## Controls

None.

## Change

- Find where the cover's snow share and `field.fs`'s snow part (the inputs, the per vertex against per fragment terms, a noise or a height term one side has and the other lacks) and make the cover read the snow the ground shows.
- Pebbles and the ore specks lie under settled snow too; boulders (up to 0.65 m) may stand above it. The design proposes what the stones do, the main agent decides.
- A fresh dusting that tufts show through belongs to the weather's snowfall (M15), not here.
- Docs: `doc/presentation.md` (the ground cover), `doc/content.md` (the cover's kinds) if a key changes; the log.

## Verify

- The checks and the suite, with a test that no plant instance stands where the ground's snow share (as `field.fs` computes it) is over a threshold the design names, at the cold spot and on a snow line.
- Captures at the cold spot and along a snow edge at eye height, sent to the user.
