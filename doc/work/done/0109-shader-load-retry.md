# 0109 Shader load retry for Gladio

Status: implemented
Milestone: M11

## Goal

On the phone (Winlator, Gladio, 2026-09-29) the shaders compile on most starts and fail on some: `SHADER: [ID 14] Failed to compile fragment shader code` for the water shader on one start, `[ID 11]` for the chunk shader on another, with the same files that compiled a minute before and after. Gladio answers `GL_COMPILE_STATUS` from its own table (`ShaderConverter_getShaderiv` in `tmp/gladiorenderer/shader_converter.c`): success while the compile is pending, failure only after a host compile failed at link time or when the shader id is missing from its table for the current context. Nothing about that is under the game's control, and the game gives up after one try and exits with "cannot load the chunk shader". The user: "the shader compilation is still flaky".

## Change

- `load_shader_pair` (`src/render_chunks.odin`) tries up to three times: after a failed `rl.LoadShader` (the default shader came back) it unloads nothing (raylib returned its default shader, which must not be unloaded), logs `shader: <name> failed to load, attempt <n> of 3` and calls `rl.LoadShader` again. The existing error line stays for the final failure. Keep the attempt loop a small procedure with the attempt count a constant `SHADER_LOAD_ATTEMPTS :: 3`.
- Both callers (`load_chunk_shader`, the water shader loader, and the hot reload path through `reload_chunk_shader`) get the retry through `load_shader_pair`; check there is no other `rl.LoadShader` call in `src/`.
- Documentation: a sentence in `doc/architecture.md` where the custom shaders are described, and an entry in `doc/log/2026-09-29.md` (tags `#windows #shaders #gladio`) with the observation and that the retry is a mitigation for Gladio's transient failures, not a fix of them.

## Verify

- `./build.sh check`, `./build.sh check-windows`, `./build.sh test`.
- User: the phone starts without a shader failure over several starts, and the log shows `attempt` lines when Gladio stumbled.

## Implemented

2026-09-29: `load_shader_pair` loads through `load_shader_with_retry` (up to `SHADER_LOAD_ATTEMPTS`, 3, with the attempt log line) and `shader_loaded`; it is the only `rl.LoadShader` call in `src/`, so the chunk shader, the water shader and the hot reload through `reload_chunk_shader` all retry. Verified here: `./build.sh check`, `./build.sh check-windows` and `./build.sh test` pass. The retry on a real Gladio failure is not verified here (no phone); that is the user's check above.
