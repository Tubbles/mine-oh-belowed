# 0069 Mission Control on screen

Status: todo
Milestone: M11

## Goal

Mission Control is a toast. A station panel with a typewriter reveal, a styled journal and a proper discovery moment.

## Deliverables

- Mission Control lines arrive in a panel with the venture's mark, a typewriter reveal and a short chime; the journal's message log uses the same styling.
- The discovery achievement (0052) gets its own small card.
- The capsule landing and the survey satellite pass are drawn on the map and in the world (0067).
- Tests: the reveal timing as a pure procedure, the audit passes with the panel.

## Verify

- Builds and tests pass.
- User: Watch a chapter beat complete.

## Notes

Implementation pointers (main agent, 2026-09-28), decisions taken so the item is unambiguous. Lands after 0068 sound (the chime goes through its sound events) and 0067 (the capsule descent it draws on the map); read both Implemented paragraphs first.

- Routing: quest notices reach the player through `ui_toast` today (`src/loop.odin`, the `notices` of `Quest_State`). A pure `notice_presentation(text_key) -> Notice_Presentation` (new `src/ui_mission_control.odin`) classifies them: keys with the `mc_` prefix are Mission Control lines, `item_discovered` is the discovery card, everything else stays a toast. `Ui_State` gains a Mission Control queue and a discovery card next to the toasts (`src/ui_core.odin`), advanced with the frame time like the toasts.
- The Mission Control panel, drawn by the HUD (`src/hud.odin`) at the top left where the toasts sit, the toasts moving down below it while it shows: a frame in the panel colour with an accent left border, the venture's mark (a small chevron drawn with two triangles, no file) and the header "MISSION CONTROL" (string `mission_control_header`), then the line revealed at `MISSION_CONTROL_CHARACTERS_PER_SECOND` (40) with a blinking cursor while revealing, held for `MISSION_CONTROL_HOLD_SECONDS` (4) after the reveal, then fading over half a second; queued lines show one after the other; Confirm while a line reveals completes it at once, a second Confirm dismisses it (the pause menu is unaffected: the panel reads Confirm only while no screen is open). The reveal timing (`revealed_characters(seconds) -> int`, the total duration) and the queue advance are pure and tested; wrap the text with `wrap_text` as the journal does. A chime plays when a line starts (`.Mission_Control` sound event through 0068's list in `Ui_State`).
- The discovery card: centred under the top edge, `DISCOVERY_CARD_SECONDS` (3): the item's icon (`draw_item_icon`, the item id resolved from the notice's argument key by the string table's reverse lookup is not available, so the notice carries the item: extend `Quest_Message` with an optional `item: Item_Id` set by the discovery code in `src/discovery.odin` where it logs the message, default `NO_ITEM`), "Discovered" (string `discovery_card_title`) and the name; a chime (`.Discovery` event).
- Journal (`src/ui_journal.odin`): message log rows for Mission Control keys get the accent left border and the mark, other rows stay plain; the row height grows to fit the border.
- On the map and in the world: during a capsule descent (0067's `Particle_Memory` in `Frame_State`, passed into the screen context as a read only pointer) the map draws a parachute marker over the pad; an orbital survey (the `orbital_survey_charted` message, `ORBITAL_SURVEY_KEY` in `src/venture.odin`) starts a satellite pass kept in the same render memory: over 6 seconds a satellite icon crosses the map from west to east through the pad, and in the world a small bright quad crosses the sky along the sun path's axis at the dome's height (draw it in the sky pass, `src/render_sky.odin`, from a `satellite_pass` value the frame passes); the message count in the memory detects the start, as 0067 detects shipments.
- Tests (`src/ui_mission_control_test.odin`): classification by key, the reveal character count over time and the total duration, the queue advancing and Confirm completing then dismissing, the discovery card timing, the satellite pass position at start, middle and end, and the UI audit with a Mission Control line revealing, a discovery card and a journal with both kinds of rows.
- Docs: `doc/ui.md` (the panel, the card, the journal rows, the map and sky events), `doc/quests.md` (Mission Control presentation line), `doc/log/2026-09-28.md`, this item's Status and Notes.

Files a subagent may touch: new `src/ui_mission_control.odin` and `src/ui_mission_control_test.odin`; `src/ui_core.odin`, `src/hud.odin`, `src/ui_journal.odin`, `src/ui_map.odin`, `src/ui_screens.odin` (the screen context fields), `src/loop.odin` (routing and the memory), `src/quest_runtime.odin` and `src/discovery.odin` (the item on the message), `src/render_sky.odin` (the satellite), `src/render_particles.odin` (the pass in the memory), `src/sound_events.odin` (the two event kinds), `src/ui_audit_test.odin`, `data/strings/en.sjson`, the docs above, this file.
