# 0070 Lore: descriptions and notes

Status: implemented
Milestone: M11

## Goal

Items, machines and technologies have names only. Descriptions carry the realism the design promises, and a Notes tab collects what the planet tells the player.

## Deliverables

- A `description_key` per item, machine and technology in data, shown in the recipe browser's detail panel, the machine panels and the technology screen, written in the venture's terse register with real names and units.
- A Notes tab in the journal: world building lines that unlock with discoveries and chapters (the asset, the lease, the station, the buyers).
- Tests: every description key exists, the audit passes with the longer panels.

## Verify

- Builds and tests pass.
- User: Read a few descriptions on the couch.

## Notes

Implementation pointers (main agent, 2026-09-28), decisions taken so the item is unambiguous. Lands after 0069; read its Implemented paragraph for the journal's row styling.

- Data: `description_key` (optional, empty means none) on every item (`data/items.sjson`, `Item_Definition` in `src/item.odin`), machine (`data/machines.sjson`, `src/machine.odin`) and technology (`data/technologies.sjson`, `src/technology.odin`), with the texts in `data/strings/en.sjson` under `describe_item_<id>`, `describe_machine_<id>` and `describe_technology_<id>`. Write every one of them: one to three sentences in the venture's register (terse, dry, real names and units, the lease and the invoice never far; read `DESIGN.md` and the `mc_` lines in the strings for the voice), each saying what the thing is, what it is for in this factory and one concrete fact (a melting point, a density, a real ore name, a rate). No lorem ipsum, no placeholders: this is the writing pass.
- Shown: the recipe browser's detail panel (`recipe_detail_panel`, `src/ui_recipes.odin`) shows the description of the recipe's first output item under the facts, wrapped; a machine panel (`machine_screen`, `src/ui_machine.odin`) shows the machine's description in dim text under its name when the panel has room (the machine side scrolls already); the technology screen's detail panel (`technology_detail_panel`, `src/ui_technologies.odin`) shows the technology's description under its cost. The panel heights grow by the wrapped lines; the UI audit checks every size.
- Notes tab: `data/notes.sjson` with `notes = [{id, title_key, text_key, unlock = {chapter = n} | {item = "<id>"} | {technology = "<id>"} | {quest = "<id>"}}]`, loaded into a `Note_Registry` (new `src/notes.odin`, in the content tables, reloaded with them, validated: keys exist, unlock targets exist, one unlock per note). A note is unlocked when the chapter is reached (the active quest's chapter or later), the item was obtained (the discovery flags), the technology researched or the quest done; the unlock is evaluated from the state each frame, nothing saved. Write twenty to thirty notes: the asset (the planet, its geology, why the ores are where they are), the lease and the contractor, the station and Mission Control, the venture and the buyers, the survey, what the deep veins mean; each unlocked by a fitting milestone (chapters, the first discovery of each ore, key technologies). The journal (`src/ui_journal.odin`) gets a Notes tab after Contracts: unlocked notes as a list on the left (newest first), the selected note's text on the right, locked notes counted at the bottom ("12 more to find").
- Tests (`src/notes_test.odin`, `src/data_strings_test.odin` or the existing string audit): every `description_key` in the shipped data exists in the string table and every shipped item, machine and technology has one; every note's keys and unlock targets resolve; the unlock rules per kind; the UI audit passes with the longer panels and the Notes tab.
- Docs: `doc/content.md` (descriptions and notes), `doc/ui.md` (where descriptions show, the Notes tab), `doc/quests.md` (notes as world building), `doc/log/2026-09-28.md`, this item's Status and Notes.

Files a subagent may touch: `src/item.odin`, `src/machine.odin`, `src/technology.odin` (the field and its validation), new `src/notes.odin` and `src/notes_test.odin`, `src/data_load.odin`, `src/data_reload.odin`, `src/data_watch.odin`, `src/loop.odin` (the content table and the screen context), `src/ui_screens.odin`, `src/ui_recipes.odin`, `src/ui_machine.odin`, `src/ui_technologies.odin`, `src/ui_journal.odin`, `src/ui_audit_test.odin`, `src/data_strings_test.odin`, `data/items.sjson`, `data/machines.sjson`, `data/technologies.sjson`, new `data/notes.sjson`, `data/strings/en.sjson`, the docs above, this file.

Implemented: `description_key` with its string check in `src/item.odin`, `src/machine.odin` and `src/technology.odin` (`description_key_problem`, the per table validators and `item_description`, `machine_description`, `technology_description`), checked after loading by `validate_content_description_keys` in `src/data_reload.odin`; 218 descriptions (142 items, 49 machines, 27 technologies) in `data/strings/en.sjson` with the keys in `data/items.sjson`, `data/machines.sjson` and `data/technologies.sjson`; the recipe detail panel (`recipe_description_item`, `src/ui_recipes.odin`), the machine panel (`machine_description_lines`, `src/ui_machine.odin`) and the technology detail panel (`src/ui_technologies.odin`) show them dim. New `src/notes.odin` (`Note_Registry`, loading and validation, `note_is_unlocked`, `unlocked_notes`) and `data/notes.sjson` with 29 notes, loaded with the content in `src/data_reload.odin`, watched by `src/data_watch.odin`, carried in `Game_Content` (`src/loop.odin`) and `Screen_Context` (`src/ui_screens.odin`); the Notes tab after Contracts in `src/ui_journal.odin`. Tests: new `src/notes_test.odin` (4 tests: the shipped notes resolve with every unlock kind, validation, the unlock rules per kind, newest first), two in `src/data_strings_test.odin` (every shipped item, machine and technology described with an existing key, the optional key check), and `src/ui_audit_test.odin` audits the Notes tab and a Notes tab with every note unlocked. One line outside the list: `src/data_reload_test.odin` writes `notes.sjson` for the reload tests, which load every content file. Docs: `doc/content.md`, `doc/ui.md`, `doc/quests.md`, decisions in `doc/log/2026-09-28.md`. 898 tests pass.
