# 0315: Float the toolchains and turn CI green

Status: todo (2026-11-07)

The user (2026-11-07): "Let's only pin when there's a good reason. Have packages float on latest as a general rule, and we'll integrate them as necessary as it shows up." CI's `nix` job has failed on every push since 2026-11-05: `flake.nix` follows `nixos-unstable`, whose Odin moved from dev-2026-09 to dev-2026-10, and the new Odin refuses the flake's `odin check src -target:windows_amd64` on Linux without `-windows-sdk-root`. The build and all tests pass there on dev-2026-10.

## Goal

CI is green on the latest toolchains, and every pin left in the repository carries its reason beside it.

## Controls

None.

## Change

- The pins found on 2026-11-07:
  - Odin dev-2026-09: the local `~/opt/odin` (`CLAUDE.md`, `doc/build.md`), and the CI `windows` and `android` jobs (release URL and SHA-256).
  - SDL3 3.4.16: the CI `windows` job.
  - The Android tools: NDK 27.3.13750724, build-tools 34.0.0 and platform 34 in `tools/android_env.sh`, which CI uses too, and the command line tools zip with its SHA-256 in `tools/android_toolchain.sh`.
  - raylib 6.0: the tag `tools/build_raylib.sh` builds the committed archives in `shared/raylib` from, with patches.
  - Not pins: nixpkgs follows `nixos-unstable` with no lock, and the GitHub actions float within their major tags.
- The `nix` job passes on dev-2026-10. Either the Windows cross check gets what the new Odin asks for, or it leaves the flake because the `windows` job builds natively on every push. The local `./build.sh check-windows` follows the same choice.
- The `windows` and `android` jobs take the latest Odin and SDL3 releases. The Android NDK and build-tools take the newest the runner holds.
- What stays pinned states why beside the pin. Candidates are raylib, whose committed archives are built with patches, and the Android platform level, a product target rather than a tool.
- The local Odin moves to the latest release only with the user's approval of the install. Until then the local and CI toolchains may differ, and the docs say so.
- Docs: `CLAUDE.md` (Stack), `doc/build.md` (the toolchain table, CI), `doc/android.md` (the tools, CI).

## Verify

- CI green on all three jobs after the push.
- The checks and the suite locally.
