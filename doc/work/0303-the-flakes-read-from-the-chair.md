# 0303: The flakes read from the chair

Status: todo (2026-11-06)

Milestone: the entry's look (0273, 0286, 0288, 0290). Follows 0290, whose flakes landed as specified but do not read from the chair: over the 120 ticks after the heat peak the shipped rate put no flake in the chair's porthole, and at the rate's maximum (100) three crossed, each a dark dot of about 3 pixels at 720p, its bright streak lost against the sheath (doc/log/2026-11-06.md, 0290). The user's ask (2026-10-05): pieces of burning material breaking off the shield like miniature asteroids, adding to the chaotic feel, each with a streak of bright plasma aft.

## Goal

From the chair at the peak a burning flake is seen most seconds, as a piece with a lit edge and a bright streak that stands out from the sheath behind it, at the footage's count and pace (0 to 2 in view, crossing in 4 to 6 frames at 30 fps, `work/reference/0288/`).

## Controls

None.

## Change

- Measure the footage first: a flake's apparent size against the window's width, how often one is in view, its brightness and its streak's length against the sheath around it; then the same of ours with the capture difference of 0290 (a clip at the shipped rate against the same ticks at rate 0).
- Tune what the numbers say: the size, the rate and its bound, where on the rim flakes are born so the chair's porthole sees its share, and the head's and the streak's light so they read over the sheath (brighter than it, or a darker and larger core with a lit rim).
- Docs: `doc/presentation.md` (The flakes), `doc/content.md` for a changed bound; the log.

## Verify

- The checks and the suite; a test of the flakes in the chair's porthole per second around the peak at the shipped rate.
- The capture difference over the 120 ticks after the peak: flakes in view in most of its seconds, each covering more than a few pixels at 720p; the clip sent to the user beside a footage strip.
