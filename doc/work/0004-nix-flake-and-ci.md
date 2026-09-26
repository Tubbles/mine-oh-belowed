# 0004 Nix flake and CI

Status: implemented
Milestone: M0

## Goal

Reproducible builds and a CI check on every push.

## Deliverables

- `flake.nix` with package, development shell and checks, pinned to nixpkgs unstable (odin dev-2026-09, raylib 6.0, sdl3 3.4.16).
- `.github/workflows/ci.yml` running the development shell and, once `src/` exists, `nix build`.

## Verify

- CI green on the first pushed commit (development shell step).
- After 0001: `nix build` succeeds in CI and the item moves to `verified`.
