# 0378: The wait from anywhere

Status: todo (2026-11-11)

0358 put the wait at the charging cradle: every connected player in a cradle, a three second settle, then eight hours pass. The user (2026-11-11): the wait is available "anywhere but the player power drain continues during the wait".

## Goal

Players wait eight hours from wherever they stand, and the wait is not a recharge.

## Controls

No world control. The pause menu gains a row "Wait", between Resume and Settings, which asks for the wait and closes the menu; while asked, the row reads "Stop waiting". The HUD line of 0358 ("Waiting for N of M") stays. The cradle keeps its seat (the inventory binding aimed at it) and no longer starts a wait by itself.

## Change

- The wait fires when every connected player has asked, after 0358's settle, through a player command under the lockstep. Moving, taking damage or any world action withdraws the ask.
- The cradle is where the charge is restored and nothing else. The charge is design text until the survival milestone (`DESIGN.md`), so the rule lands there: the eight hours drain the charge as eight played hours would, and a unit that would run out during the wait refuses it with the reason shown.
- A save made mid settle: 0358's rule for a disk load is replaced by clearing the asks.
- Docs: `DESIGN.md`, `doc/input.md`, the doc that owns the wait.

## Verify

- The checks and the suite: two players, one asking, no wait; both asking, the day offset advances by eight hours once; an ask withdrawn by a move; the state hash equal on two machines.
- A capture of the pause menu's row and of the HUD line.
