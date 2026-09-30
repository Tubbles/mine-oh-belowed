# Documentation index

[CLAUDE.md](../CLAUDE.md) holds the rules for agents, [DESIGN.md](../DESIGN.md) and [PLAN.md](../PLAN.md) the intent and the plan. The documents here say how each part works, in the present tense; the why lives in the decision log and the work items.

- [architecture.md](architecture.md): frame and tick, sessions, threads and chunk streaming, generation, world storage, the simulation, data loading, hot reload and the data edits overlay, strings, the save format, configuration and directories, logging, platform split, testing, the factory benchmark.
- [content.md](content.md): the rules behind the values in the data files: units, stack and price classes, tools, hand crafting, phase budgets, gates, veins, ratio checks, world, blocks, textures, models, sounds, descriptions, the tick cost baseline.
- [logistics.md](logistics.md): belts as transport lines, belt placement, inserters, splitters, mining drills and bore drills, loose items, item transfer.
- [fluids.md](fluids.md): fluid networks and pump head, the fluid machines, oil and chemistry, power networks with proportional brownouts, generators and dispatch order, assemblers, labs and research.
- [quests.md](quests.md): quest principles, objective types, the runtime, spawn requirements, each chapter's intent, Mission Control's tone.
- [presentation.md](presentation.md): what is drawn and heard: chunk meshes, textures and shaders, sky, weather, water, ambient life, particles, the player, machine models, sound.
- [input.md](input.md): input backends, the input frame, the Steam Controller through SDL3 and Steam Input, the Deck, Android, bindings, hold or toggle, fly mode, what is not built yet.
- [touch_overlay.md](touch_overlay.md): the touch screen's virtual gamepad, gestures and aiming, its layout file, user layouts and the editor.
- [ui.md](ui.md): the immediate mode UI, focus and pointer as one model, item slots, the touch button row, widgets, settings, the screens, text, theme and the on-screen keyboard.
- [hud.md](hud.md): the HUD over the world, targeting and placement ghosts, Mission Control and the notices, the player's hands.
- [developer_tools.md](developer_tools.md): the Developer screen, the diagnostics pages, the texture editor and the Data files screen with its export.
- [commands.md](commands.md): the command socket the assistant drives a running game with in developer mode: transport, protocol, every command, blueprints.
- [build.md](build.md): host toolchain, the shared collection and raylib archive, `build.sh`, the command line, the play build, the Steam shortcut and Deck, Nix, CI, the Windows build.
- [android.md](android.md): the native Android app: toolchain, raylib patches, entry point, link, APK, the phone's files, haptics, the keyboard, storage access for the export.
- [inspiration.md](inspiration.md): lessons taken from Factorio, Satisfactory, Dyson Sphere Program, the voxel factory games and the mod ecosystem, with sources.
- [log/](log/): dated decision logs, write once.
- [work/](work/): work items with status and verify statements.
