# 0263: The arrival texts name the pod, not the capsule

Status: verified (2026-10-05)

## Goal

A player on the field reads texts that describe their own arrival: the pod, its locker and its hatch, never a drop capsule on a pad. The block world's texts stay for block saves.

## Controls

No binding changes.

## Change

- The notes and descriptions that name the capsule get a field counterpart (a second string key chosen by the world kind, or a rewrite that fits both), decided with the chapter 1 texts of 0237's chapters table, which the arrival cutscene (0223) and the chapter items rewrite anyway; fold this item into the first chapter item if it lands first.
- `doc/content.md` (the notes), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`.
- Tests: the UI audit of the notes screen on a field session shows the pod's text; the string audit finds no missing key.
- The couch: open the notes after the stock quest on the field and read the arrival note.

## Specification (design, 2026-10-05)

Designed against `main` at bafb0d7 (0262 landed). No binding, no data key, no save layout change, no block world text changed. The fold into a chapter item does not apply: 0254 (chapters 1 to 4 on the field) is not written yet, so this item stands alone.

### The texts a field session shows that name the capsule or the pad

Found by `grep -n -i "capsule\|landing\|pad" data/strings/en.sjson` and the call sites of each key. Field variant (a new `<key>_field` string, the base key unchanged) for each one a field player can read:

| Key | Shown | Block text (unchanged) | Field variant `<key>_field` |
| --- | --- | --- | --- |
| `quest_arrival_text` | HUD objective, journal quest detail | "Touch down at the landing pad." | "Touch down in the pod." |
| `note_the_contractor_text` | journal Notes (quest bearings) | "...The venture supplies the landing, the capsule and the invoices. Clause 9 describes the capsule as a loan." | "Contractor agreement, clause 4: the contractor supplies labour, judgement and presence on the asset. The venture supplies the landing, the pod and the invoices. Clause 9 describes the pod as a loan." |
| `note_the_capsule_title` | journal Notes list and heading (quest stock) | "The drop capsule" | "The pod" |
| `note_the_capsule_text` | journal Notes (quest stock) | "The drop capsule came down with you and stays on the pad. ..." | "The pod came down with you and stays where it hit, in the crater. Rewards land in its locker and deliveries leave from it, and the two hatches of its airlock are the only way out. The venture's word for this arrangement is logistics." |
| `catalogue_ordered` | toast and journal Messages (launch pad Catalogue) | "Ordered: {name}, {value} credit. The capsule leaves with the next drop." | "Ordered: {name}, {value} credit. The venture sends it with the next drop." (no `{target}`: an orbital survey lands nowhere, fix round) |
| `developer_teleport` | developer page button | "Teleport to the landing pad" | "Teleport into the pod" (the button already teleports into the cabin on the field, 0183) |

Stay as they are, with the reason:

- `capsule_landed`, `reward_target_capsule`: already chosen by the reward target's kind (`reward_landed_key`, `reward_target_name_key`), so a field world with a locker shows `locker_stocked` and `reward_target_locker`. The `NO_ENTITY` case (a pod without a locker, no shipped data does that) still reads the capsule phrase, question 1.
- `machine_drop_capsule`, `describe_machine_drop_capsule`, `block_landing_pad`: name block world things a field session never shows (no capsule entity since 0262, no blocks).
- `item_launch_pad`, `machine_launch_pad`, the `mc_launch_pad*` and `quest_launch_pad*` lines, `note_launch_permit_text`, `item_cargo_capsule`, `describe_item_cargo_capsule`, `quest_rocket_parts_text`, `describe_technology_rocketry`: the launch pad and the cargo capsule are things the player builds, the same in both worlds.
- `describe_item_*_foundation` ("the first pad"), `describe_item_concrete`, `settings_effects_volume_tooltip` ("the landing"), `locker_stocked` ("a drop"): no capsule and no landing pad named.
- Every `mc_*` line: none names the capsule or the pad.

### Code

- `src/data_strings.odin`: `FIELD_VARIANT_SUFFIX :: "_field"` and `field_variant_key :: proc(key: string, field: bool) -> string`: `key + FIELD_VARIANT_SUFFIX` in the temp allocator when `field` and that key is in `active_string_table().entries`, else `key`. Reads the entries as `lookup_text` does and reports nothing missing. Doc comment: the field world's text of a key (0263), for the note titles and texts, the quest texts and the message texts. It goes when the block world goes (0237).
- `src/ui_journal.odin`:
  - `draw_quest_objective`: `text(quest.text_key)` becomes `text(field_variant_key(quest.text_key, screen_context.field_session))`.
  - The quest detail (the `draw_wrapped(... reward_target_text(text(quest.text_key), ...))` line): the same.
  - `journal_notes_section`: the heading `text(note.title_key)` and `text(note.text_key)` through `field_variant_key(..., screen_context.field_session)`.
  - `journal_note_list`: the row's `text(... .title_key)` the same.
  - The Messages tab: `quest_message_text(...)` gains `screen_context.field_session` as its last argument.
- `src/quest_runtime.odin`, `quest_message_text :: proc(message: Quest_Message, shipments: []Shipment, items: Item_Registry, reward_target: Entity_Handle, field: bool) -> string`: `text(message.text_key)` becomes `text(field_variant_key(message.text_key, field))`, the rest unchanged, so `{target}` in a variant is filled. No default value, so every caller states the session.
- `src/loop.odin`, `show_quest_notices :: proc(state: ^Ui_State, notices: []Quest_Message, shipments: []Shipment, items: Item_Registry, reward_target: Entity_Handle, field: bool)`: passes `field` to both `quest_message_text` calls, and its caller (the `show_quest_notices(ui, ...)` line) passes `session.simulation.field.enabled`.
- `src/ui_developer.odin`: the Teleport button's label becomes `screen_context.field_session ? text("developer_teleport_field") : text("developer_teleport")`, two literals so `test_shipped_strings_cover_the_ui` scans both keys.
- Existing test callers of `quest_message_text` pass `false`: `src/quest_runtime_test.odin` (`test_quest_texts_name_the_reward_target`, both calls), `src/venture_test.odin` (the `Shipped {cargo} for {value}` call).
- `data/strings/en.sjson`: the six `_field` keys of the table, each on the line after its base key.

### Tests

1. `test_field_variant_key_picks_the_field_text` (`src/data_strings_test.odin`). A `String_Table` parsed from `a = "A"`, `a_field = "B"`, `c = "C"`, set as `thread_string_table` (reset in a `defer`). Asserts `field_variant_key("a", false) == "a"`, `field_variant_key("a", true) == "a_field"`, `field_variant_key("c", true) == "c"`, `field_variant_key("missing", true) == "missing"`, and that the missing key is not reported (`reported_missing` empty).
2. `test_shipped_field_variants_have_a_base_and_name_the_pod` (`src/data_strings_test.odin`), on the shipped `en.sjson`: every key ending in `FIELD_VARIANT_SUFFIX` has its base key in the table, the six keys of the table above exist, and no variant's text, lowercased, contains "landing pad", and its count of "capsule" equals its count of "cargo capsule".
3. `test_a_field_session_shows_no_drop_capsule_in_the_journal` (`src/notes_test.odin`): `use_shipped_strings()`, quests and notes as `test_shipped_notes_resolve` builds them. For every note (title, text) and every quest (title, text, message, complete, every hint's text), plus `CATALOGUE_ORDERED_KEY`, `text(field_variant_key(key, true))` lowercased holds no "landing pad" and as many "capsule" as "cargo capsule", and `field_variant_key(key, false) == key` for each (the block world reads the base keys). The `the_capsule` note's field text contains "pod" and "locker".
4. `test_the_catalogue_order_names_no_capsule_on_a_field_session` (fix round: the field text holds the name, the value and no "capsule") (`src/quest_runtime_test.odin`, after `test_quest_texts_name_the_reward_target`, from `make_locker_quest_test`): `use_shipped_strings()` (reset in a `defer`), `quest_message_text(Quest_Message{text_key = CATALOGUE_ORDERED_KEY, argument_key = <an item's name key>, value = 3}, nil, test.items, locker, true)` contains no "capsule". With `field = false` and the capsule handle it equals the block text with the name and value filled (contains "The capsule leaves").
5. UI audit (`src/ui_audit_test.odin`): `audit_frame` sets `screen_context.field_session = audit_case.field_session` after `audit_screen_context`, and `audit_every_note` runs a second case `{name = "journal notes, every note, field", screens = {.Journal}, tab_next = <as the first>, walk_focus = true, field_session = true}`, so every note's field text is drawn and fitted at every audit size. The existing `hud field *` cases now draw the active quest's field text. No other screen reads the flag but the developer page.
6. Unchanged and passing: `test_shipped_notes_resolve`, `test_shipped_strings_cover_the_ui` (now finds `developer_teleport_field`).

### Docs

- `doc/quests.md`, Runtime, the bullet "In a message text `{value}` ...": append "On a field world a quest text, a message text and a note's title and text read `<key>_field` when the string table has it (`field_variant_key`, 0263), so the arrival and the notes name the pod and its locker instead of the capsule and the pad. The block world reads the base keys."
- `doc/content.md`, Descriptions and notes, the Notes bullet: append "A note whose text names the block world's capsule or pad has a field variant, `<key>_field` ([quests.md](quests.md), Runtime)."
- `doc/code_map.md`, the `data_strings.odin` line: `String_Table`, `text`, `field_variant_key`.
- `doc/log`: written by the main agent at the landing.

### Hand-back check

- Memory a frame draws from: `field_variant_key` returns the base key or a temp allocated key, and `text` of either returns the table's string as before, so a strings reload behaves as today. Nothing freed in the UI pass.
- A long string fitted at the smallest audit size: test 5 draws every field note text at every audit size, and the variants are no longer than the texts they replace (the toast and the button label shorter or equal within a few characters).
- A UI audit case made obsolete: none. The block note case stays and the field case is added.
- Tests never touch the state directory: all tests above use in-memory string tables and the shipped data through `#load`.
- The others (file writes, start-up loads, parsed numbers, save layout, shared budgets, unbounded lists) do not apply.

### Open questions, with the answer chosen

1. Field variant, rewrite for both, or unchanged: a field variant for each of the six, so every block text stays byte for byte (the item: "The block world's texts stay for block saves") and the variants become the only texts when 0237 removes the block world.
2. How the choice is made: by the session kind (`simulation.field.enabled`, as `Screen_Context.field_session`), not the reward target's kind, because the arrival and the contractor note are about the world, not about where rewards land. One procedure, `field_variant_key`, keyed by the `_field` suffix, so no data file gains a field and no registry changes. A typo'd variant cannot pass silently: test 2 requires the six keys and a base for every variant.
3. The note's id `the_capsule` stays: ids are not shown and not saved, and the block world keeps the note.

### For the main agent

1. `reward_target_name_key(NO_ENTITY)` reads "the capsule on the landing pad", which a field world shows only when its pod has no locker (no shipped data does, 0262 Part 4). Left as it is here. A third phrase ("the venture's next drop") is a small addition if you want the field never to name the capsule.
2. The suffix lookup applies only at the sites listed (note title and text, quest text, message text, the developer button). Quest titles and chapter titles do not take variants because none needs one. Say if you want them wired for uniformity.
3. The six field texts are mine, in the venture's register. The user may want to word the pod note.

### Decisions (main agent, 2026-10-05)

1. `reward_target_name_key(NO_ENTITY)` stays as it is: no shipped pod lacks a locker, and a third phrase for a case nothing reaches is text nobody reads.
2. The variant lookup stays at the sites listed. A title that needs one is wired when it needs one.
3. The six field texts are approved as written; the user rewords the pod note from the journal if they want to, after it lands.
