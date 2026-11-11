# 0360: The factory's flat draws fade at the view's end

Status: todo (2026-11-11)

Found by 0354's design: foundation slabs (`draw_frames`), belt runs and poles and torch boxes are drawn unhazed at every distance (0313 chose them so). At a 256 m view a factory 300 m away shows them standing on the faded ground with its machines faded out.

## Goal

Everything of a factory fades at the view's end as its machines do.

## Controls

None.

## Change

- The slabs, belt runs, poles and torch boxes take the haze and the end fade of `apply_haze`, or end with the view.
- After 0347, which rewrites these draws, and 0355, which removes the poles.

## Verify

- The checks and the suite.
- Captures at 256 m of a factory 300 m out, before and after, sent to the user.
