# 0262: No block world capsule in a field world

Status: landed (2026-10-05, "Start a field world without the block world's capsule (0262)", eb98d5b, installed the same day; implementer agent a0164458336c76459, verified the same day with no fix round (two low notes folded into the docs at the landing: the other frame side readers of the block body, and the reverse direction of a new field save on an older build), in `.claude/worktrees/0262` on `item/0262` from `main` at e9bb799, the specification approved the same day with the decisions below; found by the 0183 design: `make_simulation` places the block world's drop capsule in every world, so a field world carries a `drop_capsule` entity on frame 0 at the block pad (`query entities` lists it at 354 35 66 on the default seed) that nothing on the field draws, uses or saves on purpose; after 0183)

## Goal

A field world holds only the field's entities: the pod on its frame and what the player builds. The block world's drop capsule is placed only in a block world.

## Controls

No binding changes.

## Change

- `make_simulation` (or `choose_world_start`, where the block spawn search runs for every new world) places the drop capsule and runs the block spawn search only when the world is a block world; a field world's `World` carries no block pad.
- Old field saves that carry the capsule load as they are (the entity table reads what is there) or drop it with one log line; the design stage decides which and names what a joiner's snapshot does.
- Docs: `doc/architecture.md` (The field session, the start; the block world's capsule), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: a new field world's entity table holds no `drop_capsule` and `query entities` lists the pod only; a new block world (`--debug-terrain`) still holds its capsule; an old field save with the capsule loads.

## Specification (design, 2026-10-05)

Designed against `main` at 2879c5f (0183 landed). No binding, no string key, no data key, no save layout change.

### What the code does today (read and probed this session)

- `start_session` (`src/session.odin`) picks the world's start before the simulation exists: `saved_world_start` (a loaded file with `landing_pad_present`), else `choose_world_start` (`src/main.odin`), which runs `find_spawn` for every new world that is not the debug terrain and sets `generator.landing_pad`. Only after `make_session_simulation` does it compute `field := session_plays_field(plan, content)`. `session_plays_field` reads only the plan and the content (`plan.file.field_world` when loading, else planets present and not the debug terrain), so it can move up.
- `make_simulation` (`src/simulation_state.odin`) calls `place_capsule(&state.world.entities, content.machines, landing_pad)`, which already returns `NO_ENTITY` and places nothing when `!site.present`, then `make_quest_state(content.quests, capsule)`. So a start whose `landing_pad` is the zero `Landing_Pad_Site` gives a world with no capsule and `quests.capsule == NO_ENTITY`; `make_simulation` itself needs no change.
- `state.landing_pad` goes to `world.sjson` (`landing_pad_present`, `landing_pad`, `save_world.odin`); a file without it falls back to the search in `start_session`. On the field nothing else reads the pad after 0183: `teleport pad`, `query world`'s pad line and `blueprint`'s pad origin answer or run only on the block world, `draw_map_events` returns when `!pad.present`, `capsule_landing_point` finds no capsule and starts no descent, the block chunk streaming is off on the field so `generator.landing_pad` (block stamp, `add_starter_veins`) is never read there.
- The quests: chapter 1 and every objective read statistics, unlocks or the reward target, never the capsule handle. The reward target on a field world is the pod's locker (`settle_quest_reward_target` in `enable_new_field_world` and at load, 0210); `quests.capsule` is only its fallback when the pod has no locker. `--give` overflow goes to `pending_rewards`, so to the target, not to the capsule. The shipped pod has a locker (`test_a_field_world_save_round_trips_the_reward_target` asserts it).
- The block `Player` body on the field: `make_player(start.player)` puts it at the start; no field tick moves it. After 0183 its position is still read on the field by (a) the HUD's biome banner (`make_hud_context` samples `sample_column` of the block generator at `player.position`, `draw_biome_banner` draws it on the field too), (b) the F3 World page's `chunk ... biome` line (`world_facts`), (c) `lockstep.spawn` (`make_single_player_lockstep`, `make_server_lockstep`), which every machine passes to `Add_Player_Command` for a joiner's block body. The block sounds (`play_frame_sounds`) do not run on the field (`loop.odin`, `!field`). The probe below found the block column (0, 0) is `lake` on six seeds, while the default seed's spawn search column is `coastal_dunes`: moving the body to the origin turns the field's start banner from "Coastal Dunes" into "Lake". That is why part 3 gates the banner.

### Part 1: the condition and the start (the change)

The world kind as the session knows it before the simulation is made is `session_plays_field(plan, content)`; `start_session` moves that line up and branches on it.

`src/session.odin`, `start_session`: replace

```odin
	if start, saved := saved_world_start(&session.generator, plan.loading, plan.file); saved {
		session.start = start
	} else {
		session.start = choose_world_start(&session.generator, plan.debug_terrain)
	}
	session.simulation, problem = make_session_simulation(plan, config, content, session)
	session.simulation.world.planet = session.planet
	field := session_plays_field(plan, content)
```

with

```odin
	field := session_plays_field(plan, content)
	if start, saved := saved_world_start(&session.generator, plan.loading, plan.file); saved {
		session.start = start
	} else if field {
		session.start = field_world_start()
	} else {
		session.start = choose_world_start(&session.generator, plan.debug_terrain)
	}
	session.simulation, problem = make_session_simulation(plan, config, content, session)
	session.simulation.world.planet = session.planet
```

`src/main.odin`, new procedure placed just above `saved_world_start` (beside `debug_terrain_player_start`, so the code map gains no edge):

```odin
// A field world has no block spawn and no landing pad (0262): its start
// is the pod (enable_new_field_world). The block body, which holds the
// shared inventory (Player), stands on the origin.
field_world_start :: proc() -> World_Start {
	return World_Start{player = player_start_on({})}
}
```

Order matters: the saved pad wins over the field branch, so a field world saved before 0262 keeps its pad, its start and its block body where they were (Part 2), and a field world saved after 0262 (`landing_pad_present: false`) takes the field branch on load instead of the old "file without a pad" search. The new world's log loses its `world: seed N, spawn at x y z` line (the search no longer runs); no line replaces it (the home's lines of `new_world_home` already log the field start's exceptions). `session_generator` already zeroes `generator.landing_pad`, so the field's generator holds no pad.

`make_simulation`'s doc comment: "The capsule stands on the landing pad from the start" becomes "A block world's capsule stands on the landing pad from the start; a field world passes no pad and has none (0262)". `landing_pad.odin` and `make_simulation`'s code stay.

The block body's position on the field: `player_start_on({})`, feet at 0.5 1 0.5, yaw 45, the same placeholder `make_reloaded_simulation` (`data_reload.odin`) already passes. Nothing in the simulation on the field reads it (no `tick_player` on the field). Host and joiner reach the same `session.start` from the same `world.sjson` by the same rule, so their `lockstep.spawn` and a joiner's block body agree and the hash holds.

Unchanged: `--debug-terrain` (`session_plays_field` is false, `choose_world_start` returns `debug_terrain_landing_pad()`, the capsule stands), a new world without planet data (block session, spawn search, capsule on the pad), old block saves (`saved_world_start` or the search), the benchmark (`make_benchmark_simulation` passes its own pad; see question 2), `make_reloaded_simulation` (passes `old.landing_pad`, which is `{}` on a new field world, and the state is then read back from the saved bytes).

### Part 2: the old field save rule: load as it is

A field world saved before 0262 has `landing_pad_present: true` and the capsule in `entities.bin` on frame 0, with `quests.capsule` pointing at it. It loads unchanged: `saved_world_start` gives the old pad and start, `make_simulation` places a capsule that `read_entity_pools` then replaces with the saved pool, `read_quest_state` restores `quests.capsule`, the reward target settles on the locker. No code, no log line. Why this and not a drop: before 0210 a field world's rewards landed in the capsule, so an old capsule can hold items, and a drop would destroy them; a drop also needs a load step, a log line and a test of its own for a thing nobody uses (the 0183 design found nothing on the field uses it, and `query entities` on the field lists no frame 0 entity since 0183). The joiner's snapshot is the host's tables (`encode_join_snapshot` through `encode_save_files`): the joiner reads the same `world.sjson` and the same pools, so it holds the capsule exactly when the host does, and both take the same start by the order above. The capsule stays until the world is made again; nothing removes it.

### Part 3: the biome banner on the field

`src/biome_banner.odin`, `draw_biome_banner`: `if banner == nil {` becomes `if banner == nil || hud.field_session {`, and the procedure's doc comment (the banner file's header) gains: "Not on a field world: the biome is the block generator's column under the block body, which the field never moves (0262)." Without it every new field world announces "Lake" at the start (the origin's column). Struck if the main agent prefers (question 1).

### Part 4: the reward target's log line

`src/quest_runtime.odin`, `settle_quest_reward_target`: the line

```odin
		platform.log_printf("quests: the pod has no locker; quest rewards go to the drop capsule")
```

becomes

```odin
		platform.log_printf("quests: the pod has no locker; %s", target.kind == .Capsule ? "quest rewards go to the drop capsule" : "quest rewards wait, the world has no drop capsule")
```

A new field world whose pod has no locker (data without one; the shipped pod has one) now has target `NO_ENTITY`: `entity_slots` returns nil, `land_rewards` lands nothing and the stacks wait in `pending_rewards` (never dropped), deliveries count nothing. That is acceptable for data that leaves the locker out; the quest text's `{target}` phrase reads "the capsule on the landing pad" there (`reward_target_name_key` of `NO_ENTITY`), left as it is.

### Tests

All new tests use the existing fixtures; none touches the state directory.

1. `test_a_new_field_world_has_no_drop_capsule` (`src/simulation_field_test.odin`): `start_field_test_session`, `field_test_content`; asserts `pool_alive_count(state.world.entities.capsules) == 0`, `state.quests.capsule == NO_ENTITY`, `!state.landing_pad.present`, `!session.start.landing_pad.present`, `!session.generator.landing_pad.present`, `session.start.player == field_world_start().player`, `state.quests.reward_target` equal to `pod_locker`'s handle. Ticks once, `encode_save_files`, ends the session, parses the world file: `!file.landing_pad_present`; loads it (`Session_Plan{loading = true, ... files = &files}` as `test_a_field_world_save_round_trips_the_reward_target` does), `stage_generated_field_set` and `restore_arrived_field_set`; asserts the reloaded capsule count 0, `!loaded.start.landing_pad.present`, the hash equal to the one before the save.
2. `test_field_query_entities_lists_only_the_pod_frame` (`src/command_test.odin`, next to `test_field_query_world_veins_entities_and_frames`): `make_field_command_test`, `find_test_pod` for frame F; `query entities` answers ok, every line after the first holds ` frame F ` and none holds `drop_capsule`; `query entities capsule` answers `entities 0`; `pool_alive_count(test.session.simulation.world.entities.capsules) == 0`. (Frame 0 entities were already left out of the field's listing by 0183; the pool assertion is the one that fails before this item.)
3. `test_a_debug_terrain_world_keeps_its_drop_capsule` (`src/simulation_field_test.odin`): `test_field_game_config`, `make_field_test_game_content` (planets present), `Session_Plan{debug_terrain = true, seed = DEFAULT_WORLD_SEED, settings = default_world_file_settings(config)}`, `start_session`; asserts `!simulation.field.enabled`, one alive capsule, `quests.capsule != NO_ENTITY` and `entity_at(entities, debug_terrain_landing_pad().centre + CAPSULE_OFFSET) == quests.capsule`.
4. `test_a_new_block_world_keeps_its_drop_capsule_on_the_pad` (same file): content `Game_Content{simulation_content = make_save_test_content()}` (no planets), `Session_Plan{seed = DEFAULT_WORLD_SEED, settings = default_world_file_settings(config)}`; asserts `!field.enabled`, `landing_pad.present` and centre `{352, 34, 64}` (the default seed's spawn, also what `choose_world_start(&make_test_generator(DEFAULT_WORLD_SEED), false)` returns), one alive capsule at `landing_pad.centre + CAPSULE_OFFSET` equal to `quests.capsule`.
5. `test_an_old_field_save_keeps_its_drop_capsule` (same file): a new field session made into a pre 0262 world: `state.landing_pad = Landing_Pad_Site{present = true, centre = {352, 34, 64}}`, `state.quests.capsule = place_capsule(&state.world.entities, machines, that site)`, 3 coal put in the capsule's slots; one tick, the hash, `encode_save_files`, end, load as in test 1; asserts one alive capsule, `restored.quests.capsule` equal to the saved handle with 3 coal in its slots, `restored.landing_pad` equal to the site, `loaded.start.player == player_start_on({352, 34, 64})`, the reward target the locker, the hash equal.
6. `test_a_field_world_without_a_locker_or_capsule_keeps_its_rewards_waiting` (`src/quest_runtime_test.odin`, after `test_a_field_world_without_a_locker_falls_back_to_the_capsule`): `make_locker_quest_test`, remove the locker and the capsule (`remove_entity` of both), `test.state.capsule = NO_ENTITY`, `settle_quest_test_target(&test, true)`; asserts `reward_target == NO_ENTITY`; append `{coal, 7}` to `pending_rewards`, `run_quest_tick`; asserts one pending stack of 7 coal and no notice.
7. `test_biome_banner_is_not_drawn_on_a_field_session` (`src/biome_banner_test.odin`): as `test_biome_banner_draws_the_biome_of_the_hud_context` with `field_session = true` in the `Hud_Context`; after six frames `banner.shown == 0`, `!banner.showing` and the draw list has no "Mountains".
8. Unchanged and passing: the lockstep and join hash tests (`test_two_field_simulations_hash_alike_and_part_on_one_input`, `test_two_machines_spawn_alike_on_a_wet_seed`, `test_a_joiner_drops_into_a_pit_dug_under_the_cabin`, `test_a_joiner_restores_while_the_others_play_and_reaches_their_hash`, `test_two_simulations_fed_the_same_records_keep_the_same_hash`), `test_a_field_world_save_round_trips_the_reward_target` (its `restored.quests.capsule == capsule` now compares `NO_ENTITY` with `NO_ENTITY`), and the 0183 `test_field_query_world_veins_entities_and_frames`. No test pins a hash value. The probe below ran the whole suite with Part 1 applied: 1941 tests, all passed, so no existing test needs a change.

### Docs

- `doc/architecture.md`, The field session, the bullet "The start": append "A field world has no block spawn and no landing pad (0262): `start_session` asks `session_plays_field` before the start, and a new field world takes `field_world_start` instead of the spawn search, so `make_simulation` places no drop capsule and `quests.capsule` is `NO_ENTITY`; the block body that holds the shared inventory stands on the origin, which only `lockstep.spawn` and the F3 World page's chunk line read on the field. A field world saved before 0262 keeps its pad and its capsule on frame 0 as saved, and a joiner reads the host's."
- `doc/architecture.md`, Save format, the bullet ending "A file without a pad centre falls back to the spawn search.": that sentence becomes "A block world's file without a pad centre falls back to the spawn search; a field world writes `landing_pad_present: false` and runs no search (0262)."
- `doc/quests.md`, Runtime, the reward target bullet: "and the capsule with one log line when the pod has no locker" becomes "and the capsule with one log line when the pod has no locker; a field world made since 0262 has no capsule, so there the rewards wait in the pending list".
- `doc/hud.md`, the Biome banner bullet: append "Not on a field world, whose block column under the block body means nothing (0262)." (Struck with Part 3.)
- `doc/content.md`: nothing; it names the capsule only through the locker's "at least the capsule's 8" slots, which stays true.
- `doc/log/2026-10-05.md`, a new section after the 0183 section:

  ```
  ## No drop capsule in a field world (0262)

  Tags: field, capsule, landing-pad, spawn, start, quests, save, lockstep, 0262, m14

  Every new world ran the block world's spawn search and got the drop capsule on its pad, the field included, where the capsule stood on frame 0 and nothing on the field used it. A new field world now takes `field_world_start`: no search, no pad, no capsule, the block body (kept for the shared inventory) on the origin. Old field saves load as they are, capsule and pad included, rather than dropping the capsule with a log line: before 0210 a field world's rewards landed in it, so it can hold items, and a joiner reads the host's tables either way. Moving the block body showed that the biome banner read the block generator's column under it on the field ("Coastal Dunes" on the default seed, "Lake" at the origin), so the banner is off on a field world. A pod without a locker on a new field world now leaves the rewards waiting, since there is no capsule to fall back to.
  ```

### Hand-back check

- The save layout line: no layout change. `world.sjson` already carries `landing_pad_present`; a new field world writes `false`. An old field save (pad and capsule) loads as it is with no log line, by the rule of Part 2, and test 5 covers it. No dev kit reads the capsule on the field (`data/dev_kits.sjson` names the reward target).
- A new participant in a shared budget: the quest reward target loses its fallback on a new field world; Part 4 and test 6 say what happens (rewards wait, never dropped).
- Tests use temporary state only: every test above runs through `start_session` with in-memory `Save_Files` or fixtures, as the existing field save tests do.
- The others (memory freed under a frame, `.tmp` writes, start-up loads, parsed numbers, unbounded lists, UI audit cases) do not apply: nothing is freed, written, parsed or listed anew. The UI audit's banner case (`ui_audit_test.odin`) builds a `Hud_Context` without `field_session`, so it still draws.

### Verify

- `taskset -c 8-15 nice -n 10 ./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md` (no new file and no new cross cluster call: `field_world_start` lives in `main.odin` beside `choose_world_start`).
- The tests above by name.

### Open questions, with the answer chosen

1. The banner (Part 3): gate it on the field, or leave it announcing the block column's biome ("Lake" from now on)? Chosen: gate it; the alternative turns a wrong but plausible start banner into a wrong and obviously wrong one, and the gate is one condition. The main agent may strike Part 3, its test and the hud.md line.
2. The benchmark (`make_benchmark_simulation`) still places a capsule on its block floor's pad before `start_benchmark_field`. Chosen: unchanged; it is a test world with a block floor, not a new world from `start_session`, and removing it changes its entity counts. Item of its own if wanted.
3. Old field saves keep their capsule forever. Chosen: yes (Part 2). A later item could move its contents into the locker and drop it, if the user wants old worlds clean.

### Questions to the main agent

1. The F3 World page's `chunk ... biome` line on the field reads the block body too and will print `chunk 0 0 0 biome Lake` instead of the spawn column's. Leave it (a developer page, already meaningless on the field), or fold a field form of the line into this item? Not specified here.
2. The lore note `note_the_capsule_text` ("The drop capsule came down with you and stays on the pad") and the capsule's description now describe a thing a field world lacks. Not touched (text, out of this item's scope); a work item if the notes are shown on the field.

### What the design ran

- A `git archive` copy of 2879c5f under the scratchpad, with `build.sh`'s `test` passing extra flags, run with `taskset -c 8-15 nice -n 10 ./build.sh test -define:ODIN_TEST_NAMES=...`.
- `game.test_probe_0262` on the unchanged copy: a new field session holds one alive capsule, `quests.capsule` a capsule handle, the reward target the locker, the pad and block body at 352 34 64 / 352.5 35 64.5; the block body's column is `coastal_dunes`, the origin's `lake`; for seeds 20260927, 1, 2, 3, 42 and 12345 the spawn search took 2 to 18 ms and the origin column was `lake` every time.
- With Part 1 applied in the copy, `test_probe_0262_new`, `_old` and `_block`: a new field world has 0 capsules, `quests.capsule` `NO_ENTITY`, the locker as target, no pad, the body at 0.5 1 0.5, `world.sjson` with `landing_pad_present: false`, and reloads with 0 capsules, the field start and an equal hash; a pre 0262 field world (pad and capsule with 3 coal placed by hand) reloads with its capsule, its 3 coal, the same handle, its pad and start and an equal hash; the debug terrain session (with planets) and a block world without planets keep their capsule on their pad (352 34 64 for the block world) with the `world: seed 20260927, spawn at 352 34 64` line only for the latter.
- The full suite on that copy: 1941 tests, all successful.

### Decisions at the approval (main agent, 2026-10-05)

1. Question 1: folded in, as a skip. On a field session the F3 World page's `tick ... chunk ... biome ...` line (`diagnostics.odin`, `append_line` of the chunk and biome) prints the tick only, since the chunk and the biome are the block world's and the field's feet line (0183's `field_feet_coordinates`) already says where the player is; a field biome readout comes with the biome items of 0237. One assertion in the diagnostics tests: a field session's World page holds no `biome` word.
2. Question 2: the capsule's lore note and description are item 0263, which the chapter items of 0237 may fold in. Not this item.
3. The banner gate (part 3) and the log line (part 4) stay as specified. The old save rule (load as it is, no log line) is approved: a capsule can hold items from before 0210.
