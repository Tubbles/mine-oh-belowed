# 0302: Tech demos on the title, the shim retired

Status: todo (2026-11-06)

Milestone: the water tech demo (0291). The user (2026-11-06): the tech demos move into the real game as a main menu option called "tech demos", instead of being reached through their own `update-and-run.sh` shim.

## Goal

The play build (`tools/install_play_build.sh`, the "Mine oh Belowed" Steam shortcut) is the one way into the tech demos: its title has a "Tech demos" button that lists the demos, today the water one. `update-and-run.sh` and the tech demo's own Steam shortcut are gone.

## Controls

Control design (main agent, 2026-11-06), no new binding, no world control touched:

- Title: the "Water tech demo" button becomes "Tech demos", in the same place (after New world, before Load).
- A new title screen `Tech_Demos`: a heading "Tech demos", one button per demo (today "Water", which pushes the existing `Tech_Demo` screen), then Back. Navigated as every title screen: D-pad focus, Confirm (A) selects, Back (B) pops. Back on the water screen returns to this list.
- `--tech-demo` alone opens the title with `Tech_Demos` and the water screen pushed, so Back walks the same way as from the title. `--tech-demo=<model>,<radius>,<start>` is unchanged.

## Change

- `ui_title.odin` (the button and its string), a `Tech_Demos` screen beside `ui_tech_demo.odin`, the screen enum and its dispatch, the bare flag's push in `loop.odin`, the strings.
- Remove `update-and-run.sh` and `add_steam_shortcut.py --tech-demo` (its app name, its target, its flag).
- Docs: `doc/build.md` (the command line row, the Steam shortcut, The water tech demo section), `doc/ui.md` (Title, the new screen, the screens table), `doc/code_map.md`.

## Verify

- The checks and the suite; the UI audit draws `Tech_Demos` and walks its focus at the smallest audit size, and the water screen's audit case starts from it.
- A test: the title's Tech demos button pushes `Tech_Demos`, its Water button pushes `Tech_Demo`.
- A headless screenshot of the title and of the Tech demos screen.
