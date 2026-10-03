# 0103 Windows log beside the executable

Status: implemented
Milestone: M11

## Goal

On the phone the game ends at once, and the user cannot reach the log: the Windows build writes it to `%LOCALAPPDATA%\mine-oh-belowed\log.txt` inside the Wine container, which GameNative keeps in its private app data. The user (2026-09-28): "Just put the logfile next to the binary for now". The folder the user unzipped is on the phone's shared storage and is the one place they can read.

## Change

- On Windows, `open_log_file` (`src/logging.odin`) writes `log.txt` into the executable's directory (`os.get_executable_directory`, as `data_directory_relative_to_executable` in `src/data_load.odin` does), not into the state home. When the executable directory cannot be found, the log stays off as it does today when no state directory is found, with the same one stderr line. Linux is unchanged: `$XDG_STATE_HOME/mine-oh-belowed/log.txt`.
- Only the log moves. Screenshots and `texture_edits.sjson` stay in `%LOCALAPPDATA%\mine-oh-belowed` (`platform_paths.odin`); the command socket has no Windows side.
- Keep the split pure: a small procedure that gives the log directory for the platform, chosen with a `when ODIN_OS == .Windows` block around the call, so `log_directory_from_environment` and its callers (`command_socket.odin`, `texture_generate.odin`, `platform_paths_test.odin`) stay as they are.
- Documentation in the same commit: the header comment of `src/logging.odin`, the comment in `src/platform_paths.odin` (the state home no longer holds the log on Windows), `doc/build.md` (the "Where files land under Wine" paragraph), `doc/architecture.md` (the two sentences naming the Windows log path), the README text in `.github/workflows/ci.yml` (the `log:` line: `log.txt beside mine-oh-belowed.exe`), and the user verify line of `doc/work/done/0102-windows-build-for-gamenative.md`. Add a dated entry to `doc/log/2026-09-28.md` (tags `#windows #logging #decision`): the log sits beside the executable on Windows because GameNative's container is not reachable from the phone's file manager, screenshots and texture edits stay in the state home for now.

## Verify

- `./build.sh check`, `./build.sh check-windows`, `./build.sh test`.
- `tools/wine_smoke_test.sh` prints the log from beside the executable it ran (its last `find` under the prefix goes), so the check after the next CI run reads: the start writes `log.txt` next to `mine-oh-belowed.exe` in the unzipped artifact, and the `AppData\Local` log gains no new header line. No Windows executable can be built here (the Linux `./build.sh release` gives an ELF), so that run waits for CI.
- User: on the phone, `log.txt` appears in the unzipped folder after a start.

## Implemented

2026-09-28. `platform_log_directory` (`src/logging.odin`) gives the executable's directory on Windows and the state home elsewhere, and `open_log_file` takes the log directory from it; `log_directory_from_environment` and its other callers are unchanged. When the executable directory cannot be found the log stays off silently, as it does today when no state directory is found (today's path prints no stderr line there either). `tools/wine_smoke_test.sh` prints `log.txt` from beside the executable it ran. Verified here: `./build.sh check`, `./build.sh check-windows`, `./build.sh test` (1050 tests). Not verified: the Wine run of the smoke test, which waits for the next CI artifact (no Windows executable can be built here), and the phone.
