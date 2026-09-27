# 0054 Hot reload of data while the game runs

Status: todo
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
