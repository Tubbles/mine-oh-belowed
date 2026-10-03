# 0188: The Multiplayer screen: every game hosts, the LAN lists the games to join

Status: todo (playtest 1 of the slice, 2026-10-03; the user's priority before the rest of the playtest)

## Goal

Every game played is a multiplayer game, as in Minecraft: a windowed session hosts on the LAN from its first tick with no "host" action, and the title's Multiplayer screen lists the games the LAN answers so a player picks one and joins. A later toggle "open or close this game to others" (not this item) will gate the joins; for now every game is open. Today a host is `--server` only (headless, no local player), a joiner `--join=<address>`, and the title has no multiplayer entry (playtest 1).

## Change

- Hosting: a windowed session runs the server's relay and the join snapshot beside its local session (`session_server.odin`, `session_network.odin`), from the first tick, offline play unchanged; `--server` stays for a headless host. The listener takes `DEFAULT_NETWORK_PORT` and, when that port is taken (two games on one machine), the next free one of a small range, logged, so a second game on the same machine still hosts.
- Discovery, UDP in the platform package beside the TCP transport (`src/platform/network.odin`, the same build tags, so Windows and the phone have it where they have the transport): the Multiplayer screen broadcasts a query once a second while open (to the limited broadcast address and to each interface's broadcast address); every hosting game answers the sender with one datagram: a protocol tag and version, the world's name, the host machine's name, the players on it and the cap, the TCP port, the build stamp. Nothing else crosses the discovery port.
- The screen: a Multiplayer button on the title between Load and Settings; the screen lists the games answered within the last three seconds (world, host, players, build), focus navigation and the pointer, Confirm joins through the path `--join` uses, a game of another build greyed and marked since the host refuses it anyway; one "Join by address" string field row under the list as the fallback for networks that drop broadcasts (the phone needs an IP address, it has no resolver); Back. The notice while the join runs and the failure toast as today.
- A toast on the host when a machine joins or leaves ("2 players on this game").
- `doc/architecture.md` (Multiplayer: every session hosts, the discovery), `doc/commands.md` (the flags beside the screen; the ports a firewall must pass, since Fedora's firewalld blocks incoming connections by default: the TCP port range and the UDP discovery port), `doc/ui.md` (the screen, its audit case), `doc/android.md` if the phone needs anything for broadcasts, the log.

## Verify

- The build and check commands of 0168, `./build.sh check-windows` included; the UI audit at every size with the Multiplayer screen, empty and with three games listed.
- Tests: a hosting session answers a discovery query over the loopback with its world name and port and a query with no host lists nothing; two sessions on one machine take different ports and both answer; the screen's list from a set of answers (the draw list test), a stale answer dropped after three seconds; a join from the list through the loopback hashes alike with the host over a thousand ticks (the existing join test over the new path).
- The couch: two machines on the home network, the second sees the first in the list and joins; a split screen pair on either; the firewall note tried on the laptop.
