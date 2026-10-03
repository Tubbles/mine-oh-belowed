# 0104 GL driver line in the log

Status: implemented
Milestone: M11

## Goal

On the phone (2026-09-28, GameNative or a sibling app, the user changed a setting between two starts) the window now opens on an X11 session at 1280 by 720, and the start fails one step later: raylib logs "SHADER: [ID 12] Link error: Link failed because of missing fragment shader." and the game gives up on the chunk shader. The vertex shader passes. No compile warning precedes the link error, so whatever translation layer sits between Wine and the phone's GPU (GL4ES converts to GLSL ES 1.00, VirGL compiles on the host) reports only at link time, and the log does not say which layer it is or what GLSL level it offers. The fragment shaders are the only ones with `uint` bit operations and `dFdx`.

The next log from the phone must name the GL implementation, so the shader fix aims at a known target.

## Change

- After the window opens (where `log_display_diagnostics` runs, `src/loop.odin` and `src/display.odin`), log one line `gl: vendor <GL_VENDOR>, renderer <GL_RENDERER>, version <GL_VERSION>, glsl <GL_SHADING_LANGUAGE_VERSION>`, through `log_printf` like the display line, once per start (not on every display change).
- Get `glGetString` through GLFW's loader, not through a link against libGL or opengl32: add `glfwGetProcAddress :: proc(name: cstring) -> rawptr ---` to the foreign block in `shared/raylib/platform.odin` (GLFW is inside raylib's archive on both systems, and raylib itself loads GL this way) and cast the result to `proc "c" (name: u32) -> cstring`. The enum values: `GL_VENDOR 0x1F00`, `GL_RENDERER 0x1F01`, `GL_VERSION 0x1F02`, `GL_SHADING_LANGUAGE_VERSION 0x8B8C`. A nil procedure or a nil string logs `unknown` for that field rather than crashing.
- Keep the formatting pure and tested: a procedure that takes the four strings and returns the line, with a test in `src/display_test.odin` (or a new `src/gl_info_test.odin`), covering the `unknown` fallback.
- Documentation in the same commit: the logging paragraph of `doc/architecture.md` (one sentence: the gl line and why), `shared/raylib/platform.odin`'s header comment (the new GLFW call), and an entry in `doc/log/2026-09-28.md` (tags `#windows #shaders #logging`) recording the phone's link error, the vertex/fragment split, the GL4ES and VirGL facts above, and that the gl line exists so the shader work targets a known GLSL level.
- No shader changes in this item.

## Verify

- `./build.sh check`, `./build.sh check-windows`, `./build.sh test`.
- `./build.sh release` links (the new GLFW symbol resolves from the archive on Linux; Windows resolves on CI).
- User: on the couch and on the phone, the log has a `gl:` line after the display line.

## Implemented

2026-09-28: `log_gl_info` runs once in `run_game` right after the first `log_display_diagnostics`, not on the display change path. `gl_info_text` and the nil procedure case of `gl_string` are covered by `test_gl_info_text`. Verified here: `./build.sh check`, `./build.sh check-windows`, `./build.sh test`, and `./build.sh release` links with `glfwGetProcAddress` resolved from `libraylib.a`. Not verified here: the Windows link (CI) and the line on the couch and the phone (user).
