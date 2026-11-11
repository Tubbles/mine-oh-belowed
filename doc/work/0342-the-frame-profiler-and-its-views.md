# 0342: The frame profiler and its views

Status: todo (2026-11-11)

0340's research found that nothing has ever timed a frame on the couch's GPU: the F3 frame time includes the wait for the display, and the cost items (0310, 0311, 0328) left estimates. The target (the user, 2026-11-11): 60 frames a second on average at 1080p and 60 Hz on the couch, with the view at 512 m, in split screen too, with an early game factory of a handful of machines; the Steam Deck is a target, the phone secondary.

## Goal

A table of what a frame costs on the couch's GPU in fixed views, CPU and GPU apart, repeatable from one command in the night window without the TV, so every later performance item is chosen and accepted by it.

## Controls

None.

## Change

- A frame profile in the game: the frame's CPU sections, the GPU's time for the frame and its passes, the tick's sections, the draw calls and vertices of the field's renderer, read through the command socket and shown on the F3 Render page (whose counters are the block renderer's today).
- Fixed views (the home, the spring, a forest, a lake, a cave mouth after 0327, a ridge line, an early factory of a handful of machines, each also in split screen, at a 512 m and a 1024 m view) set through the command socket, and a script that runs them and writes the table.
- The run: under a nested `gamescope --backend headless -W 1920 -H 1080`, which gave the game the RX 5700 on 2026-11-11 with no TV and no root (the `gl:` line of `tmp/gamescope_try/out.log`), vsync and the frame cap off, a session that reads no device (0341), its own runtime directory so its command socket cannot meet a play session's, the GPU's clock and load logged beside the timers and never forced. A benchmark under the global rules: 03:00 to 06:00 Europe/Stockholm, `~/benchmark.lock`.
- The trial's log read `window 1920 x 1080, render 1280 x 720`: whether the game draws at 720p on a 1080p display is settled here first, since it changes the fill by 2.25 times.
- Docs: `doc/architecture.md` (Performance: the method, the budget, the table), `doc/build.md` (the command), `doc/commands.md`.

## Verify

- The checks and the suite.
- The night's table on `main` for every view against the budget, with the `gl:` line naming the RX 5700, sent to the user.
