# 0320: Shaders compiled by Mesa in the checks

Status: todo (2026-11-07)

0307's `field.vs` named a parameter `packed`, a reserved word in GLSL. glslangValidator and the suite passed it, and Mesa refused it, so the field drew nothing in the headless capture and would have drawn nothing on the couch. 0307's second fix round compiled every shipped shader pair through Mesa with no window: a Python ctypes script using the system `libEGL.so.1` on the surfaceless platform (`EGL_PLATFORM_SURFACELESS_MESA`), with `LIBGL_ALWAYS_SOFTWARE=1`, as GLSL 3.30 and as GLSL ES 3.00 (rewritten as `shader_source_for_gles` does). The script is kept at `tmp/0320/mesa_shader_check.py`. The same run found that a stale overlay `field.vs` from before 0307 links with the new `field.fs` on desktop Mesa, where GLSL ES refuses the pair.

## Goal

Every shader pair the game loads is compiled and linked by a real driver in the checks, on desktop GLSL and on GLSL ES, before an item reports.

## Controls

None.

## Change

- The script becomes a repository tool beside `tools/check_docs.py`, run from a `build.sh` mode over every pair the game loads (`load_shader_pair` callers), in both dialects. It prints the info logs and exits nonzero on a failure. A machine without EGL or Mesa gets a message saying the check was skipped, never a pass.
- `CLAUDE.md` (Implement) and the verify stage run it, and CI's `nix` job runs it if Mesa's software driver is available there.
- The reserved word rule joins the shader rule in `CLAUDE.md` (Code rules), next to the `u` suffix.
- Docs: `doc/build.md` (build.sh, the checks), `doc/presentation.md` (the shader rules).

## Verify

- The mode fails on a copy of `field.vs` with `packed` restored, and passes on the shipped shaders.
- The checks and the suite.
