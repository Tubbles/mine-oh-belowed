# 0210: The pod's locker takes the capsule's quest rewards on a field world

Status: landed (2026-10-03, 6066930; verifier: land as is, the log wording and two nits fixed at landing; implemented 2026-10-03; designed 2026-10-03; main agent, from the 0198 design's question 2; after 0198)

## Goal

Quest rewards are delivered to the drop capsule, and the quest texts name it. On a field world the capsule sits on the block frame, out of the player's way, while the pod's locker (0198) is the chest they live beside. The locker should be the field world's capsule: rewards land in it and the texts name it.

## Change

- The quest state's reward target is the pod's locker on a field world (the first `pod_locker` entity of the first pod) and the capsule on a block world; the delivery counting that reads the capsule's inventory reads the target's.
- The strings that name the capsule in quest texts take the target's name on a field world (a key per target, or the machine's name key substituted).
- `doc/content.md` (Quests, the reward target), the log.

## Controls

- None.

## Verify

- The build and check commands of 0168.
- Tests: a field world's quest reward lands in the locker and the delivery counts it; a block world's still lands in the capsule; a save round trips the target.

## Specification (design, 2026-10-03)

### Decisions

- **The target is derived, not saved.** `Quest_State.capsule` stays the capsule's handle, saved as today. The target is derived from the saved pools at two moments, a new field world (`enable_new_field_world`) and every load (`read_simulation_state`, which also serves a joiner's snapshot and the content reload), and kept in a new unsaved field `Quest_State.reward_target`. Every machine derives it from the same pools, so the lockstep agrees, and the save layout does not change: no remap, no format bump. `write_quest_state` writes fields one by one, so the new field stays out of the bytes and out of `simulation_state_hash`.
- **"First", defined:** the first pod is the first alive entry of `entities.foundations.entries` in index order whose machine is of kind `Pod`. This is the pod `field_pod_spawn` already spawns players in. The locker is the first alive entry of `entities.chests.entries` in index order whose machine is of kind `Locker` and whose `frame` is that pod's frame. A save writes both pools with their entries and free lists (`write_pool`) and restores the frames before the derivation runs (`read_later_tables`), so a save round trips the target exactly.
- **When it is derived:** at a new world and at load only, not every tick. The locker cannot change during play: it has no item, so pick up refuses it (`entity_frames.odin`, the `item == NO_ITEM` check) and the developer `remove` refuses it too (doc/commands.md). The pod changes only at load (`upgrade_resized_pods`). If the target ever dies mid-game, `entity_slots` returns nil: rewards wait in `pending_rewards` and are never dropped, and the next load falls back.
- **The baseline moves with the target.** When the derived target differs from `reward_target`, `statistics.capsule_totals` is snapshotted from the new target (`snapshot_capsule`). Without that, an older field save's locker contents would count as delivered on the first tick, since `observe_capsule` counts growth against the snapshot. For a save of this build the snapshot is a no-op: `snapshot_capsule` runs at the end of every `tick_quests`, and nothing writes the locker between ticks. `test_a_field_world_save_round_trips_the_reward_target` checks this through hash equality.
- **Fallback:** on a field world without a locker (content without one, a data reload that drops it), the target is the capsule and one log line reports it at that load or new world. Nothing fails.
- **Strings: a key per target, substituted at a `{target}` mark.** The machine name keys were rejected. `machine_drop_capsule` is "Drop capsule" and `machine_pod_locker` is a title case label. Neither reads mid-sentence ("to Drop capsule"), and the capsule's phrase needs "on the landing pad" to tell a new player where it is. Two new keys hold a phrase per target. The eight quest texts that name the capsule get the mark. The notice gets a key per target, because "A capsule has landed" is a whole sentence of fiction, not a name.

### Code

`src/entity_pod.odin`
- Add `pod_locker :: proc(entities: ^Entities, machines: Machine_Registry) -> (locker: Entity_Handle, found: bool)`. It returns the first pod's locker as defined above and guards `int(entry.machine) < len(machines.machines)` on both pools, as `upgrade_resized_pods` does. It is called by `quest_reward_target`. Add a line to the file's header comment: the locker is the field world's quest reward target (0210).

`src/quest_runtime.odin`
- Constants: `MESSAGE_TARGET_MARK :: "{target}"`, `REWARD_TARGET_CAPSULE_KEY :: "reward_target_capsule"`, `REWARD_TARGET_LOCKER_KEY :: "reward_target_locker"` and `LOCKER_STOCKED_KEY :: "locker_stocked"` (beside `CAPSULE_LANDED_KEY`).
- `Quest_State`: add `reward_target: Entity_Handle` after `capsule`, with this comment: "where rewards land and deliveries count (0210): the capsule, or the pod's locker on a field world. Derived (`settle_quest_reward_target`), never saved." Update the comment on `pending_rewards` to say "room in the reward target".
- `make_quest_state`: also set `reward_target = capsule`. Its signature is unchanged, so every test fixture and `make_simulation` gets the capsule as the target.
- Add `quest_reward_target :: proc(entities: ^Entities, machines: Machine_Registry, capsule: Entity_Handle, field_enabled: bool) -> Entity_Handle`. It is pure: on a field world with a locker (`pod_locker`) it returns the locker, otherwise `capsule`. It is called by `settle_quest_reward_target`.
- Add `settle_quest_reward_target :: proc(quests: ^Quest_State, statistics: ^Statistics, entities: ^Entities, machines: Machine_Registry, field_enabled: bool)`. It derives the target. When `field_enabled` is true and the target is not a `.Chest` handle, it logs `platform.log_printf("quests: the pod has no locker; quest rewards go to the drop capsule")`. When the target differs from `quests.reward_target`, it sets the field and runs `snapshot_capsule(statistics, entity_slots(entities, target))`. It is called by `enable_new_field_world` and `read_simulation_state`. It needs `import "platform"` in this file, the import `entity_pod.odin` uses.
- Add `reward_target_name_key :: proc(target: Entity_Handle) -> string`, which returns `REWARD_TARGET_LOCKER_KEY` for a `.Chest` handle and `REWARD_TARGET_CAPSULE_KEY` otherwise (so `NO_ENTITY` reads as the capsule).
- Add `reward_landed_key :: proc(target: Entity_Handle) -> string`, which returns `LOCKER_STOCKED_KEY` for a `.Chest` handle and `CAPSULE_LANDED_KEY` otherwise.
- Add `reward_target_text :: proc(template: string, target: Entity_Handle) -> string`, which is `replace_message_mark(template, MESSAGE_TARGET_MARK, text(reward_target_name_key(target)))`, in the temp allocator.
- `quest_message_text`: add a fourth parameter `reward_target: Entity_Handle` and apply `reward_target_text` to the result after the value mark.
- `tick_quests`: use `entity_slots(entities, state.reward_target)` in place of `state.capsule`, and use `reward_landed_key(state.reward_target)` for the notice's key. Rename the local `capsule_slots` to `target_slots`. Leave the field `Quest_View.capsule_slots` and the procedures `observe_capsule`, `snapshot_capsule` and `consume_deliveries` as they are (no rename in this item).
- Header comment (lines 6 to 23) and the comments on `consume_deliveries` and `land_rewards`: say "the reward target (the capsule, or the pod's locker on a field world)" where they say "the capsule".

`src/simulation_field.odin`
- `enable_new_field_world`: after `place_pod`, call `settle_quest_reward_target(&state.quests, &state.records.statistics, &state.world.entities, machines, true)`. Add "the quests' reward target" to its comment.

`src/save_state.odin`
- `read_quest_state`: after `read_value_of(reader, &quests.capsule)`, set `quests.reward_target = quests.capsule`.
- `read_simulation_state`: after `finish_pod_upgrades`, call `settle_quest_reward_target(&state.quests, &state.records.statistics, &state.world.entities, content.machines, state.field.enabled)`, with a comment line: the reward target is derived from the restored pools (0210).
- `known_message_key`: accept `LOCKER_STOCKED_KEY` beside `CAPSULE_LANDED_KEY`.

UI and tools, all reading the target in place of `capsule`:
- `src/ui_journal.odin`: in `journal_quest_view`, set `capsule_slots = entity_slots(..., screen_context.quest_state.reward_target)`. In `draw_quest_objective` (line 157) and `journal_quest_detail` (line 295), use `reward_target_text(text(quest.text_key), quest_state.reward_target)` (the screen context's quest state). In `journal_message_log` (line 323), pass `screen_context.quest_state.reward_target` to `quest_message_text`.
- `src/loop.odin`: `show_quest_notices` gains `reward_target: Entity_Handle` as its last parameter and passes it to both `quest_message_text` calls. The caller at line 1290 passes `session.simulation.quests.reward_target`.
- `src/command.odin`: line 1135 uses `state.reward_target`. The help line at 94 becomes "items into the inventory, the rest to the quest reward target".
- `src/venture_test.odin:120`: add `NO_ENTITY` as the fourth argument.

### Data

`data/strings/en.sjson`:
- New: `reward_target_capsule = "the capsule on the landing pad"`, `reward_target_locker = "the locker in the pod"`, `locker_stocked = "A drop has reached the locker"` (after `capsule_landed`).
- Changed, with "the capsule on the landing pad" or "the capsule" replaced by `{target}`: `quest_invoice_text`, `quest_first_contract_text`, `quest_extraction_rights_text`, `quest_deep_mining_permit_text`, `quest_launch_pad_permit_text` ("Deliver ... to {target}."), and `mc_invoice` ("... delivered to {target}."), `mc_first_contract` ("One hundred, to {target}. ..."), `mc_extraction_rights` ("Concrete and brass, to {target}."). On a block world the three mc lines now read "the capsule on the landing pad", one phrase per target.
- Left alone, because they are not quest texts naming the delivery point: `describe_machine_drop_capsule`, the notes `note_the_contractor_text` and `note_the_capsule_text`, `catalogue_ordered` (the capsule as the vehicle) and `quest_arrival_text` (the pad).
- Data comments: `data/quests/chapter_01.sjson` lines 30 and 78 say "the reward target (the capsule on the landing pad, the pod's locker on a field world)". Change the one word in `data/dev_kits.sjson` line 8 and `data/contracts.sjson` line 14 the same way.
- No new data keys, no bounds.

### Save

Nothing is saved and the layout does not change. The reasons are in Decisions. The behaviour change for an older field save (a 0198 build's) goes in the decision log, not into a remap. Pending rewards now land in the locker. Items already in the capsule stay there. A deliver objective in progress counts again from the locker's contents at load, so plates already in the capsule no longer count toward it.

### Tests

In `src/quest_runtime_test.odin`, all on `make_quest_test` with `place_test_pod(&test.entities, test.machines)` and `test_pod_fixture(..., TEST_LOCKER)` from `entity_pod_test.odin`:
- `test_a_field_worlds_quest_reward_lands_in_the_locker_and_its_delivery_counts`: one quest that delivers 5 iron plates and rewards 7 coal. After `settle_quest_reward_target(..., true)`, `reward_target` is the locker. 5 plates are put into the locker and one tick runs. Assert: the quest is done (`active == NO_QUEST`), `statistics.delivered[plate] == 5`, the locker holds 7 coal and no plate, every capsule slot is empty, and the last notice's key is `LOCKER_STOCKED_KEY`.
- `test_settling_on_the_locker_does_not_count_its_contents_as_delivered`: 5 plates are in the locker before the settle, then one tick runs. Assert the quest is still active (`active == 0`). Then 5 more plates go in and one tick runs. Assert it is done.
- `test_a_block_worlds_quest_reward_still_lands_in_the_capsule`: the same quest with a pod placed but `field_enabled = false`. Assert `reward_target == test.state.capsule`, the reward lands in the capsule, the locker stays empty, and the notice is `CAPSULE_LANDED_KEY`.
- `test_a_field_world_without_a_locker_falls_back_to_the_capsule`: place the pod, `remove_entity` the locker, then settle with `true`. Assert `reward_target == test.state.capsule` and a queued reward lands in the capsule.
- `test_quest_texts_name_the_reward_target`: `quest_message_text(Quest_Message{text_key = "Deliver to {target}."}, nil, test.items, locker)` contains `text(REWARD_TARGET_LOCKER_KEY)` and not `MESSAGE_TARGET_MARK`. With the capsule handle it contains `text(REWARD_TARGET_CAPSULE_KEY)`. `reward_target_text` with `NO_ENTITY` gives the capsule's phrase.

In `src/simulation_field_test.odin`:
- `test_a_field_world_save_round_trips_the_reward_target`: `start_field_test_session`, then two `tick_field_test_simulation`. Assert `reward_target` is `pod_locker`'s handle and differs from `quests.capsule`. Put 3 of an item into the locker, tick once (so the snapshot follows), and take `simulation_state_hash`. Then `encode_save_files`, `end_session` and load through `start_session` with `files`, as `test_a_field_world_save_round_trips` does, including `stage_generated_field_set` and `restore_arrived_field_set`. Assert `reward_target` and `capsule` are the original handles and the hash is equal, which shows that the load's settle changed no snapshot.

In `src/data_strings_test.odin`, `test_shipped_strings_cover_the_ui`: add `REWARD_TARGET_CAPSULE_KEY`, `REWARD_TARGET_LOCKER_KEY`, `LOCKER_STOCKED_KEY` and `CAPSULE_LANDED_KEY` to the last explicit key list.

### Docs

- `doc/quests.md` owns the topic. `doc/content.md` has no Quests section.
  - Principles: the rewards bullet adds "on a field world the pod's locker (0210)".
  - Objective types: the intro and the deliver row say "the reward target".
  - Runtime: "Delivered items leave the reward target then".
  - Runtime, new bullet: "The reward target (0210, `quest_reward_target`): the capsule on a block world, the first pod's locker on a field world (first in the pools' index order), derived at a new world and at load and never saved, the delivery baseline snapshotted from it when it changes, and the capsule with one log line when the pod has no locker".
  - Runtime, the marks bullet: add `{target}` with its two keys.
  - Runtime, the notices bullet: "the capsule landing (on a field world the locker's)".
- `doc/content.md`, The pod's fixtures, the locker bullet: replace "The capsule keeps the quest rewards (0210 moves them)." with "On a field world it is the quests' reward target: rewards land in it and deliveries count in it ([quests.md](quests.md), Runtime)."
- `doc/commands.md`: the `give` row says "the rest into the pending rewards, which land in the reward target", and the `chapter` row says "items to the reward target".
- `doc/code_map.md`: the `entity_pod.odin` line adds `pod_locker`. The `quest_runtime.odin` line adds "the reward target (`quest_reward_target`, `settle_quest_reward_target`)". Raise the world cluster's "Reaches into: simulation" count by what `tools/code_graph.py --check` reports for `save_state.odin`, with the note "the quests' reward target settled at load and the locker's toast key in `save_state.odin` N (0210)".
- `doc/log/2026-10-03.md`, new section "## The pod's locker takes the quest rewards (0210)", with these bullets:
  - the target is derived, not saved, and why
  - the definition of "first"
  - the strings: a key per target at `{target}` over machine names, and why
  - the old field save's behaviour change: pending rewards to the locker, capsule contents stay, a deliver in progress counts from the locker
  - the fallback

### Hand-back check lines that apply

- A changed save layout or a behaviour change that stops old saves: the layout is unchanged. The behaviour change is named in the log bullet. The dev kits (`give_kit`, `give_to_player`) append to `pending_rewards`, so they land in the target without a change.
- A start-up load the game can make fail: a missing locker falls back to the capsule with one log line (the fallback test).
- A new participant in a shared budget: the locker is the player's storage too. A reward that does not fit waits in `pending_rewards` (`land_rewards`, unchanged). `consume_deliveries` takes only the objective's count. Inserters may pull from it as from the capsule (`item_transfer.odin`, chests and capsule alike). The shipped locker has 16 slots and the capsule 8, so every valid deliver count fits (`quest.odin:461`).
- Tests touch no state directory: the field round trip uses `encode_save_files` in memory.
- The others (frame memory, file writes, parsed numbers, unbounded lists, UI audit cases) do not apply.

### Open questions, answered

- Which locker on several pods or lockers: the first by the pools' index order, as `field_pod_spawn` picks its pod.
- A locker removed or missing: the target falls back to the capsule and a line is logged. Rewards are never dropped.
- The pod replaced at load (0198's upgrade): the settle runs after `finish_pod_upgrades`, so it finds the new pod's locker.

### For the main agent

1. Items already in a field world's capsule from an older save (landed rewards, plates delivered toward a running quest) stay in the capsule. Moving them into the locker at load would need a saved flag to tell an old save from a new one, and I could not check whether the capsule on the block frame is reachable from the field. Should a one-time move be added (a save flag and a log line), or is leaving them acceptable?
2. The three mc lines on a block world change from "to the capsule" to "to the capsule on the landing pad" (one phrase per target). Accept this, or use two phrases per target (long and short)?
3. A content edit could ship a locker with fewer than 8 slots (`MAXIMUM_CHEST_SLOTS` allows 1). A deliver of 8 full stacks would then never fit. Should the locker's minimum slots become `CAPSULE_SLOT_COUNT` in the locker validation (`machine.odin:491`)? I left it out of scope.

### Approval (main agent, 2026-10-03)

Approved as written, with the three questions answered:

1. Items already in an older field save's capsule stay there. Those saves are this week's development saves, the capsule still exists on the block frame, and a one-time move would add a saved flag for a case no released save has. The log bullet names it.
2. One phrase per target. On a block world the three `mc_` lines read "to the capsule on the landing pad"; that is mission control's own phrasing and a second, short key per target is not worth two more strings.
3. In scope: the locker validation (`machine.odin`, the locker's slot bound) takes `CAPSULE_SLOT_COUNT` as its minimum, so a content edit cannot ship a locker a delivery of eight full stacks never fits; the test that refuses too many slots gains a case that refuses seven, and the data header's line on the locker's bound says 8 to 48. The shipped 16 stays.

Implementation starts from `main` (0198 landed, 6169d29) in `.claude/worktrees/0210`.
