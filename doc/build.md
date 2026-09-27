# Build

## Host toolchain (couch machine, Bazzite)

- Odin release dev-2026-09 (nightly build a2fb372) extracted to `~/opt/odin-linux-amd64-nightly+2026-09-01`, with a stable symlink `~/opt/odin`. Source: the `odin-linux-amd64-dev-2026-09.tar.gz` asset of the GitHub release. Odin drives the linker through `clang`, which Homebrew provides (clang 23).
- raylib 6.0 is bundled with Odin as `vendor:raylib` (static `libraylib.a`, GLFW based). It links against the system `libdl`, `libpthread` and `libX11`.
- Bazzite is an immutable image with runtime libraries but without development symlinks: `libX11.so.6` exists, `libX11.so` does not, so linking fails with `cannot find -lX11`. The fix that avoids layering packages onto the image is a shim directory of symlinks to the runtime libraries, passed with `-extra-linker-flags:"-L<dir>"`. `build.sh` creates `tmp/linker-shims/` with `libX11.so -> /usr/lib64/libX11.so.6` and `libSDL3.so -> /usr/lib64/libSDL3.so.0`. Verified 2026-09-26 by compiling and linking a raylib hello world.
- SDL3: the host `libSDL3.so.0` is 3.4.16 (Fedora 44 package). `vendor:sdl3` links `system:SDL3`, so the same shim applies.

Commands (`build.sh` uses the toolchain at `${ODIN:-$HOME/opt/odin/odin}`):

```
./build.sh            # debug build (-debug) to build/mine-oh-belowed
./build.sh debug      # same as above
./build.sh release    # optimised build (-o:speed) to build/mine-oh-belowed
./build.sh check      # odin check src -vet -strict-style
./build.sh test       # odin test src
```

Both build modes pass `-vet -strict-style` and `-extra-linker-flags:"-L<repository>/tmp/linker-shims"`, creating the shim directory first.

Command line (parsed with `core:flags` in Unix style, `--help` or `-h` prints the usage page and exits): `config` (prints the configuration files found and the effective values, no window), `--set=<key>=<value>`, `--load=<world>`, `--name=<world>`, `--unlock-all`, `--version`, `--input=sdl3` or `--input=raylib` (default: SDL3 with raylib fallback), `--seed=<unsigned 64 bit decimal>` (default a fixed constant so runs are reproducible), `--debug-terrain` (the fixed 8 by 2 by 8 chunk test terrain instead of the generated world, nothing streams). A bad command line exits with status 2, a failed start with status 1.

At run time the game looks for its data directory in this order: `$MINE_OH_BELOWED_DATA` if set, `./data`, then `<executable directory>/../share/mine-oh-belowed/data` (the layout the Nix package installs). `bin/mine-oh-belowed --version` prints the version without opening a window.

## Steam library shortcut

`tools/install_play_build.sh` builds a commit (HEAD, or the commit given as its argument) in release mode from a `git archive` into `bin/play/` with its own copy of `data/`, and writes the launcher `bin/mine-oh-belowed` that runs it. The installed game never reads the working tree, so agents editing `src/` and `data/` cannot break a couch session; run the script after every landed commit that should reach the couch. `tools/add_steam_shortcut.py` adds or updates the "Mine oh Belowed" non-Steam shortcut in `~/.steam/steam/userdata/<user>/config/shortcuts.vdf`, pointing at that launcher. It parses the binary VDF, refuses to write unless the existing file round trips through its parser byte for byte, and keeps the other shortcuts untouched. Steam must be closed while it runs (check with `pgrep -x steam`), otherwise Steam overwrites the file on exit. `--dry-run` shows what would be written. Steam Input for the shortcut is disabled by hand in Steam's controller settings for the game, see `input.md`.

## Nix

`flake.nix` provides `packages.default` (the game), `devShells.default` (odin, raylib, sdl3) and `checks`. nixpkgs unstable ships odin dev-2026-09, raylib 6.0 and sdl3 3.4.16, matching the host. The nixpkgs Odin package deletes the bundled raylib libraries and patches `vendor:raylib` to link the system raylib, which is why raylib is a build input. It does not patch the `vendor:raylib/rlgl` sub package, which still names the deleted `../linux/libraylib.a`, so importing rlgl fails to link under nix. The flake overrides the Odin package with the same substitution for rlgl and adds libX11, which rlgl's import block still links. Nix is not installed on the couch machine, so the flake is validated by CI, not locally.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and pull request on `ubuntu-latest`: enters the development shell and prints the Odin version, then runs `nix build`, which compiles the game with `-vet -strict-style` and runs `odin test src` inside the build.
