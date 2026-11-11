# 0371: A standing player's tick

Status: todo (2026-11-11)

Found by 0367's design in 0342's check table: `field_players` is most of the tick in every view but the spring's, 0.35 to 0.93 ms for one player standing still. Four players in split screen would pay it four times.

## Goal

A player who stands still costs the tick next to nothing.

## Controls

None.

## Change

- Find what the player's tick does at rest (the collision's sweeps, the trunks, the ground query) and skip what cannot change the state, bit identical.
- After 0342's night table, which says what it costs uncapped.

## Verify

- The checks and the suite, with a paired run whose state hashes are equal at every tick.
