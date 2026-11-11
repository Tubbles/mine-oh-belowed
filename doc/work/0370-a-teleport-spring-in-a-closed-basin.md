# 0370: A teleport spring in a closed basin

Status: todo (2026-11-11)

Found by 0367's design: under the teleport water model sources only add and nothing above the sea takes water away, so a spring in a closed basin grows a pool for ever and its water never reaches a repeating state. 0367's savings do not meet its target there.

0367's probe (2026-11-11, 7,200 ticks at the tech demo's spring, both models): the one spring sample pours 180 fill a tick, a little over 0.7 of a sample; nothing leaves the loaded set, a chunk that is not loaded being a wall; the water stands against the set's edge within 10 seconds and a pool grows there without end, under teleport and under bodies alike (the fill grows by 108,000 a 600 tick window). Under teleport the pull is pinned at its 20,000 visits a tick from about tick 3000. So this is not only a closed basin's matter: every spring whose stream leaves the loaded set pools at its edge, and it is what keeps the tick up after 0367's savings.

## Goal

A spring's water reaches a steady state that costs nothing to hold.

## Controls

None.

## Change

- A sink (evaporation or seepage by area, in integers) or a steady stream held as a rate and not as moving samples, decided by the design from 0367's probe figures.
- After 0367.

## Verify

- The checks and the suite, with 0367's report test showing the tick at rest in a closed basin.
