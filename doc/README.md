# Documentation index

Progressive disclosure: [DESIGN.md](../DESIGN.md) and [PLAN.md](../PLAN.md) at the root are the overview. The documents here go one level deeper. Each topic gets its own file when there is enough substance to write down.

- [architecture.md](architecture.md): frame and tick, sessions, threads, generation, world storage, simulation, data loading and hot reload, the data edits overlay, save format, configuration and directories, logging, platform split, testing, the factory benchmark.
- [presentation.md](presentation.md): what is drawn and heard: chunk meshes, textures and shaders, sky, weather, water, ambient life, particles, player and machine models, sound.
- [build.md](build.md): host toolchain, the raylib archive and linker shims, `build.sh`, the command line, the play build, the Steam shortcut and Deck, Nix, CI, the Windows build.
- [android.md](android.md): the native Android app: toolchain, raylib patches, entry point, link flags, APK, the phone's files, haptics, the IME, storage access for the export.
- [fluids.md](fluids.md): fluids and gravity, pipe networks, steam, electric networks with proportional brownouts, the assembler, lab and technology screen.
- [logistics.md](logistics.md): belts as transport lines, ramps and lifts, inserters, splitters, the burner mining drill on veins, the item transfer interface.
- [ui.md](ui.md): the immediate mode UI, focus and pointer as one model, item slots, the touch row, widgets, settings, the screens, text, theme and the on-screen keyboard.
- [hud.md](hud.md): the HUD over the world, targeting, placement ghosts, Mission Control, notices and the player's hands.
- [developer_tools.md](developer_tools.md): the Developer screen, the diagnostics pages, the texture editor and the Data files screen with its export.
- [quests.md](quests.md): quest principles, objective types, chapter 1 beat by beat, chapters 2 to 8 in outline, Mission Control's tone.
- [content.md](content.md): living catalogue of items, machines, recipes, technologies and veins with their values, the rules behind the values, phase budgets and ratio checks.
- [input.md](input.md): input backends, the input frame, the Steam Controller through SDL3 and Steam Input, the Deck, Android, bindings, hold or toggle, fly mode.
- [touch_overlay.md](touch_overlay.md): the touch screen's virtual gamepad, gestures and aiming, its layout file, user layouts and the editor.
- [commands.md](commands.md): the command socket the assistant drives a running game with in developer mode: transport, protocol, every command, blueprints.
- [inspiration.md](inspiration.md): lessons taken from Factorio, Satisfactory, Dyson Sphere Program, the voxel factory games and the mod ecosystem, with sources.
- [log/](log/): dated decision logs, write once.
- [work/](work/): work items with status.

Planned before their milestones start: `world.md`, `lore.md`.
