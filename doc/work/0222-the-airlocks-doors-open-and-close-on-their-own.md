# 0222: The airlock's doors open and close on their own

Status: todo (2026-10-04, from the user's pod notes of the art rounds, repeated on the phone the same day with the round three preview ("the doors stay open? I want them to only open individually when the player is really close and then close behind the player"): today the arrival opens both and nothing closes them; "doors that automatically open and close, but tightly enough so the player will have both doors closed around themselves while being in the middle", split off 0221 by its design stage; after 0221)

## Goal

The pod's two shutter doors work as an airlock without a press: a door opens for a player who comes to it and closes behind them, and the two never stand open at once, so a player crawling through has both doors closed round them in the middle, as the user asked. The user's words of the preview: a door opens only when the player is really close to it, the two open individually, and a door closes behind the player.

## Controls

No binding changes. Interact on a hatch stays as the override (it opens or closes the door as today, within the interlock: it refuses to open a door while the other is open). The automatic behaviour is lockstep state, hashed and saved like the toggles, never presentation.

## Change

- A lockstep step after the players move, per pod (`tick_pod_airlocks` or the name the design stage chooses): a door opens when a player's capsule stands within one cell of its outer side (the lane's cells before the inner door, the cells before the outer door) or crouches in the bore facing it, and only while the other door is closed (the interlock); it closes once no capsule meets its cells or its approach cells for a short hold (so a player who steps back does not see it flap). The hold is a data key of `data/game.sjson` with bounds.
- The arrival (0200) opens both doors at the fall's end so the player walks out; the interlock takes over after the first door closes. The design stage says how a loaded old world that starts with both closed behaves.
- The hatch cue (`play_hatch_sounds`) already plays every toggle, automatic ones included; a door that opens and closes on a fixed period would be a perceivable repetition, so the hold varies by a hash of the hatch and the tick, within its bounds (`DESIGN.md`, No perceivable repetition).

## Verify

- Tests: a crouched player entering the bore from the cabin has the inner door open and the outer closed, then both closed in the middle, then the outer open and the inner closed as they leave; the lockstep hash agrees between two machines over the sequence; Interact on the far door while the near one is open is refused.
- The couch: walk out and back in without a press, and never see both doors open at once after the arrival.
