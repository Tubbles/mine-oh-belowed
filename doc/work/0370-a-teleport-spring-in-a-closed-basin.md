# 0370: A teleport spring in a closed basin

Status: todo (2026-11-11)

Found by 0367's design: under the teleport water model sources only add and nothing above the sea takes water away, so a spring in a closed basin grows a pool for ever and its water never reaches a repeating state. 0367's savings do not meet its target there.

## Goal

A spring's water reaches a steady state that costs nothing to hold.

## Controls

None.

## Change

- A sink (evaporation or seepage by area, in integers) or a steady stream held as a rate and not as moving samples, decided by the design from 0367's probe figures.
- After 0367.

## Verify

- The checks and the suite, with 0367's report test showing the tick at rest in a closed basin.
