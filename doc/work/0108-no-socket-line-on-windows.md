# 0108 No socket error line on Windows

Status: implemented
Milestone: M11

## Goal

On Windows the log says `error: command socket: no command socket on Windows` whenever developer mode is on. The user (2026-09-29): "no socket on windows is not an error". The Windows build has no command socket by design (work item 0102), so the line is noise with the wrong prefix.

## Change

- `update_command_server_open` (`src/loop.odin`) does nothing on Windows: add a constant `COMMAND_SOCKET_SUPPORTED` (`true` in `src/command_socket_posix.odin`, `false` in `src/command_socket_windows.odin`) and put it into the first case of the switch, so no open is attempted and nothing is logged. The stub `open_command_server` stays as it is.
- `doc/architecture.md`'s command socket sentence for Windows says the developer mode leaves the socket out silently; the README text in `.github/workflows/ci.yml` keeps "no command socket". An entry in `doc/log/2026-09-29.md` (tags `#windows #logging`).

## Verify

- `./build.sh check`, `./build.sh check-windows`, `./build.sh test`.
- User: a Windows start with developer mode has no `command socket` line.

## Implemented

2026-09-29: `./build.sh check`, `./build.sh check-windows` and `./build.sh test` pass on Linux. The Windows start itself is not run here, the user checks the log on the phone.
