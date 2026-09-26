# Build

## Host toolchain (couch machine, Bazzite)

- Odin release dev-2026-09 (nightly build a2fb372) extracted to `~/opt/odin-linux-amd64-nightly+2026-09-01`, with a stable symlink `~/opt/odin`. Source: the `odin-linux-amd64-dev-2026-09.tar.gz` asset of the GitHub release. Odin drives the linker through `clang`, which Homebrew provides (clang 23).
- raylib 6.0 is bundled with Odin as `vendor:raylib` (static `libraylib.a`, GLFW based). It links against the system `libdl`, `libpthread` and `libX11`.
- Bazzite is an immutable image with runtime libraries but without development symlinks: `libX11.so.6` exists, `libX11.so` does not, so linking fails with `cannot find -lX11`. The fix that avoids layering packages onto the image is a shim directory of symlinks to the runtime libraries, passed with `-extra-linker-flags:"-L<dir>"`. `build.sh` creates `tmp/linker-shims/` with `libX11.so -> /usr/lib64/libX11.so.6` and `libSDL3.so -> /usr/lib64/libSDL3.so.0`. Verified 2026-09-26 by compiling and linking a raylib hello world.
- SDL3: the host `libSDL3.so.0` is 3.4.16 (Fedora 44 package). `vendor:sdl3` links `system:SDL3`, so the same shim applies.

Commands (they arrive with work item 0001):

```
./build.sh            # debug build to bin/mine-oh-belowed
./build.sh release    # optimised build (-o:speed)
odin check src -vet -strict-style
odin test src
```

Until then, a manual build looks like this:

```
~/opt/odin/odin build src -out:bin/mine-oh-belowed -extra-linker-flags:"-L$PWD/tmp/linker-shims"
```

## Nix

`flake.nix` provides `packages.default` (the game), `devShells.default` (odin, raylib, sdl3) and `checks`. nixpkgs unstable ships odin dev-2026-09, raylib 6.0 and sdl3 3.4.16, matching the host. The nixpkgs Odin package patches `vendor:raylib` to link the system raylib, which is why raylib is a build input. Nix is not installed on the couch machine, so the flake is validated by CI, not locally.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and pull request on `ubuntu-latest`: enters the development shell and prints the Odin version, then runs `nix build`. The build step is skipped while `src/` does not exist, so the workflow stays green until milestone M0 adds source.
