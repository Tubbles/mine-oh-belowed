# 0364: Belt dead ends without the scan

Status: todo (2026-11-11)

Found by 0351's design: `record_belt_dead_ends` costs the belt lines times the inserters every tick.

## Goal

The dead ends are known without a scan of every line against every inserter each tick.

## Controls

None.

## Change

- The dead ends kept up to date where a belt or an inserter is placed or removed, or found through a spatial lookup, with the tick's result bit identical.
- After 0342, whose tick sections say what it costs today.

## Verify

- The checks and the suite, with a paired run whose state hashes are equal at every tick.
