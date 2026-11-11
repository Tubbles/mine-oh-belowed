# 0363: Gap belts

Status: designed (2026-11-11)

Part B of 0351's specification (`doc/work/0351-machine-sleep-and-gap-belts.md`), split off by the main agent since it touches about 90 test sites and Part A does not need it: a belt lane stores the gap to the item ahead, so a backed up lane skips its compressed run and a flowing lane stops at the first item moving at full speed, with the positions of today's per item rule exactly.

## Goal

A belt lane's tick costs its moving fronts, not its items.

## Controls

None.

## Change

- As 0351's specification, Part B. A change of representation only, so it holds whether or not belts run where no player is (open, `SUGGESTIONS.md`).
- After 0342, whose belt tick section says what it gains, and whose figures bear on the user's open question on the belts.

## Verify

- The checks and the suite, with the property tests of the gap lanes against today's rule and the paired runs' state hashes equal at every tick.
