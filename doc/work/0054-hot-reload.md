# 0054 Hot reload of data while the game runs

Status: implemented
Milestone: M11

## Goal

User request (2026-09-27): change data on the fly while the game runs on the couch. Presentation data reloads the moment its file changes; the content tables reload on request through the save and load path with remapping, so a world never breaks because of a half edited file.

## Deliverables

- A watcher polling the data directory's files (mtime and size, once a second, on the main thread) and the shaders directory. Strings, bindings, developer kits, biome and vein visual parameters, shaders, and later textures and models (0060, 0055) reload in place on change: a failed parse shows a toast and a log line naming the file and the problem, the old data stays.
- Content tables (blocks, items, fluids, machines, recipes, technologies, quests, contracts, vein types, biomes, veins) reload on request only: the `reload` command (0053), a Developer screen button and F8. The world is snapshotted through the save codec into memory, the data is loaded and validated as at start, and the snapshot is read back with the content remap (0047), so added, removed and reordered content behaves exactly as across builds. On any validation failure the old data and the running world stay and the problem is shown.
- The generator's data (biomes, veins) counts as content: reloading regenerates nothing already loaded (existing chunks keep their blocks) and only affects chunks loaded afterwards; say so in the toast.
- A `--watch-data=<off|presentation|all>` command line option and setting (default presentation in developer mode, off otherwise).
- Tests: the watcher notices a changed mtime, a bad strings file is refused and the old table kept, a content reload round trip over the save test's world keeps the world equal, an added item after reload is usable.

## Verify

- Builds and tests pass.
- User: edit a string in `data/strings/en.sjson` while playing and see it change; edit a recipe and run `tools/moc reload`.

## Notes

Implemented by a subagent (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (9 new tests in `src/data_watch_test.odin` and `src/data_reload_test.odin`), `./build.sh`, `./build.sh release`, `--watch-data=bad` refused, `config` lists `watch_data`, a new world `--seed=1` started and loaded through the new loader up to "could not open a window" (scratch saves directory, removed).

Files: new `src/data_watch.odin` (watcher, categories, the mode), `src/data_reload.odin` (loading the game data into an arena, the content table changes, the simulation and session rebuild), `src/hot_reload.odin` (the frame loop's side: presentation reloads, the content reload, toasts and log lines); changes to `src/main.odin` (the shared loader, `--watch-data`, the binding overrides kept), `src/loop.odin` (frame state, F8, the loop hooks, the `reload` command), `src/save_world.odin` (`encode_entities` and `decode_entities` shared by saves and reloads), `src/data_strings.odin` (`replace_string_entries`), `src/render_chunks.odin` (shader reload, atlas replacement), `src/logging.odin` (error line capture), `src/settings.odin`, `src/configuration.odin` and `src/configuration_output.odin` (the `watch_data` setting, enums by lower case name), `src/input_actions.odin` and `data/bindings.sjson` (`Reload_Data` on F8), the Developer screen, `src/command.odin`, strings.

### Model

- Categories: `strings/en.sjson` strings, `bindings.sjson` bindings, `dev_kits.sjson` developer kits, `shaders/chunk.vs` and `chunk.fs` shaders (presentation, reloaded in place at once); `blocks`, `items`, `fluids`, `machines`, `recipes`, `technologies`, `contracts`, `biomes`, `veins` and `quests/*.sjson` content; `game.sjson` restart (a toast says it applies at the next start); anything else (blueprints, editor backups) ignored. Biomes and veins have no purely visual fields, so both are content.
- The watcher polls once a second (wall clock, main thread, after the frame): a recursive scan of the data directory by modification time and size. The first poll only records.
- `watch_data`: `default` (presentation with developer mode on, else off), `off`, `presentation`, `all`. `--watch-data=off|presentation|all` overrides the setting for the run and is not written back. With `all`, a poll that finds the content files unchanged after a poll that saw them change asks for the reload (the one second quiet period).
- Content reload (the `reload` command, F8 in developer mode, the Developer screen's Reload data, `all`): the data loads into a new arena exactly as at start (main uses the same `load_game_data`); any failure keeps everything. Then `encode_entities` of the running world, a fresh simulation made like a loaded save's, `decode_entities` with the content remap, and the loaded chunks moved over with their blocks remapped (the unloaded modified chunks' palettes too). A loaded chunk holding a block the new data lacks refuses the reload, like a region file does on load. The session's scaled technologies, generator (new generator data, the world's seed, richness and pad) and streaming workers are rebuilt; the recipe and technology browsers start over, the statistics view loses its focus, the map view recollects. The atlas and the belt renderer are made again and every loaded chunk is remeshed. The old arena is freed after the swap. Toast and answer: the ids added and removed per table.

### Deviations

- `watch_data` has a fourth value, `default`, so the default can follow developer mode, which the settings screen can switch at run time.
- Every loaded chunk is remeshed on a content reload, not only those whose palette changed: the atlas layout and block visuals may have changed without a remap.
- Replaced string tables are kept until exit instead of freed at the swap: `recipe_names` held `text()` results across frames (now refreshed on a strings reload), and other long lived copies could not be ruled out. A table is small.
- F8 works only in developer mode, like the command socket and the Developer screen.
- `game.sjson` is not reloaded (tick rate and starting items belong to the start); a change shows a toast.
- Pending developer requests queued in the frame of a content reload are dropped.

### Not verified

Anything with a window: the toasts, the Developer screen row (label and button in one row, the panel one row taller), F8, the shader swap on a real GL context (`UnloadShader` of the old program), the atlas replacement and the remesh burst, the watcher against an editor's save pattern.

### Not covered

- Light from blocks whose emission changed is not recomputed in loaded chunks.
- After a `veins.sjson` change, chunks loaded later generate from the new tables, but a vein whose id (region and index) is registered already keeps its old record (`register_vein` skips known ids), so such a chunk's outcrops can disagree with the registered vein.
- Chunks in the keep margin but outside the load radius stay dirty with their old meshes until they come into range.
- A strings parse error names the file and the parser's error kind, not the line.
