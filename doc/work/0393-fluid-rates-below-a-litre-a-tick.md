# 0393: Fluid rates below a litre a tick

Status: todo (2026-11-13)

From the user's question on 0374's port floor (2026-11-13): 60 L/s is a massive stream, and the floor should be about 0.1 L/s.

## Goal

A fluid rate in data means what it says down to about 0.1 L/s, and the shipped figures are sized like real streams.

## Change

- `litres_per_tick` (`src/fluid_machine.odin`) gives whole litres a tick, at least one, so every rate under 60 L/s runs at 60: the steam engine's 30 L/s takes a litre a tick. Rates accumulate credits instead (the hand-back check's rule, as `take_power_step` does for power), in whole litres or in a finer unit, which the design decides with the save remap that follows.
- The floors `MINIMUM_PIPE_LITRES_PER_SECOND` and the fluid port's (0374) drop to what the unit carries; the iron tank and the docking connector get their own figures back.
- The shipped rates (pumps and pipes at 1200 L/s, the boiler at 60) are reviewed against the new floor. Changing them changes the chapters' balance, so the figures are the user's to approve.

## Verify

- The checks and the suite, with a rate under a litre a tick delivering its litres over a minute to the litre.

## Direction (user, 2026-11-13)

A shifted fixed point counter, 64 bit, at about a decilitre. The main agent proposes the unit 1/600 L (a decilitre a second for one tick at 60 Hz), so every rate given in whole decilitres a second is a whole number of units a tick and needs no credits; a plain decilitre unit would still truncate 0.1 L/s to nothing in a tick.
