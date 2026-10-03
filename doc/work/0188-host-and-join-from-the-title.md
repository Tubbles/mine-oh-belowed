# 0188: Host and join from the title and the pause menu

Status: todo (playtest 1 of the slice, 2026-10-03; before the multiplayer couch test)

## Goal

A session is hosted and joined from the screens, gamepad first, so the couch test needs no command line. Today a host is `--server` only (a headless process without a window or a local player) and a joiner `--join=<address>`, and the title has no multiplayer entry (playtest 1: "there is no multiplayer option on the main screen").

## Change

- Hosting: a windowed session hosts its world on the LAN, started from the pause menu ("Host on the network", with the port) or ticked on the new world and load screens; the host plays as it does offline, its machine running the server's relay and the join snapshot (`session_server.odin`, `session_network.odin`) beside the local session. `--server` stays for a headless host.
- Joining: a "Join" entry on the title opens a screen with the address (a string field, the keyboard's one use, with the last addresses remembered in the settings) and a Join button; the notice while the join runs and the failure toast as `--join` shows them today.
- Leaving: a joiner's pause menu says it is a guest; a host's pause menu lists the joined players and lets the host stop hosting (the guests fall back to the title with a notice).
- `doc/architecture.md` (Multiplayer), `doc/commands.md` (the flags beside the screens), `doc/ui.md` (the screens, the audit cases) updated.

## Verify

- The build and check commands of 0168; the UI audit at every size with the join screen and the host's pause menu.
- Tests: a windowed host and a joined simulation hash alike over a thousand ticks through the loopback; a join to an address with no host toasts the failure; the remembered addresses round trip the settings.
- The couch: two machines on the home network, one hosting from the pause menu, one joining from the title, and a split screen pair on the host.
