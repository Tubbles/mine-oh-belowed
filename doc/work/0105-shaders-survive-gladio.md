# 0105 Shaders that survive Gladio

Status: implemented
Milestone: M11

## Goal

On the user's phone (Winlator, Mali GPU, 2026-09-29) the window opens and the game dies loading the chunk shader: "SHADER: [ID 12] Link error: Link failed because of missing fragment shader." with no compile log. The `gl:` line (work item 0104) reads `vendor ARM, renderer Gladio, version 3.3, glsl 3.30`. Gladio is Winlator's OpenGL wrapper over the phone's GLES driver (source in `brunodev85/winlator-app`, `app/src/main/cpp/gladiorenderer/src/shader_converter.c`, a copy under `tmp/gladiorenderer/` here). It answers `GL_COMPILE_STATUS` with success while the compile is pending, rewrites the GLSL line by line into GLSL ES 3.20 and compiles it at link time on the phone, and its compile error goes to the phone's logcat, never to the program.

The rewriting pass `implicitConvertIntToFloat` (for legacy GLSL that assigned integers to floats) runs on every line with an operator: when any word of the line is a registered variable of a float type (`float`, `vec2`, `vec3`, `vec4`, including `const` globals), every bare integer literal on that line gets `.0` appended and every variable of type `int` or `ivec` is wrapped in `float()` or `vecN()`. `uint` and `uvec3` are unknown to its type table, so those variables are left alone, and a literal with a `u` suffix is not an integer to its `is_int`. Both fragment shaders have exactly one such line:

    return 1.0 + brightness_jitter * (float((hash >> 8) & 255u) / 127.5 - 1.0);

`brightness_jitter` is a `const float`, so `8` becomes `8.0` and `hash >> 8.0` does not compile. The vertex shaders have no integer literals, which is why they pass. The other shifts (`hash >> 16`, `hash >> 15`, `(hash >> 3) & 15u`, `(hash >> 7) & 15u`) share their lines with no float variable, so they survive today, but only by luck.

## Change

- In `data/shaders/chunk.fs` and `data/shaders/water.fs`, every integer literal carries the `u` suffix: `hash >> 16u`, `hash >> 15u`, `(hash >> 3u) & 15u`, `(hash >> 7u) & 15u`, `(hash >> 8u) & 255u`. Nothing else in the shaders changes; the hash stays bit for bit the same (shifting a `uint` by a `uint` literal is the same operation), so `texture_variation.odin`'s CPU mirror and `texture_periodicity_test.odin` stay as they are.
- A test, `src/shader_source_test.odin`, reads every `.vs` and `.fs` under `data/shaders` (find the data directory the way `src/data_watch_test.odin` does), strips `//` comments and preprocessor lines (`#version`), and fails on any bare integer literal: a maximal run of `[0-9a-fA-FxX.]` characters that starts with a digit, is not part of an identifier (no letter, digit or `_` right before it), contains no `.`, and does not end in `u`. Keep the scanner a small pure procedure over a string and test it on its own with a few lines (`x >> 8`, `x >> 8u`, `1.0`, `0x7feb352du`, `vec2(1.5)`, `atlas_uv2` must not trip). The failure message names the file, the line and the literal, and says why: Winlator's Gladio appends `.0` to it on a line with a float variable.
- Documentation in the same commit: a sentence in `doc/architecture.md` in the rendering part (shaders are GLSL 330 and every integer literal carries `u`, because Winlator's Gladio rewrites bare integers to floats on lines with float variables; the test guards it), a line under Code rules in `CLAUDE.md` (shaders: integer literals with the `u` suffix, see the test), the comment at the head of `chunk.fs` and `water.fs` gets one sentence on the rule, and a dated entry in `doc/log/2026-09-29.md` (new file, tags `#windows #shaders #gladio #decision`) with the diagnosis above: the gl line, Gladio's deferred compile, the exact rewriting rule, the line that broke, and that the CPU side is untouched.
- No other shader changes. If the shaders contain a construct you think Gladio also mangles, write it in the Implemented paragraph, do not change it.

## Verify

- `./build.sh check`, `./build.sh check-windows`, `./build.sh test` (the new test passes on the fixed shaders; check that it fails when you put `>> 8` back, then restore).
- `./build.sh release` and a start on the couch still render (the user; the Linux GL compiles `8u` and `8` the same way).
- User: the phone shows the title screen and a world.

## Implemented

2026-09-29: every integer shift amount in `chunk.fs` and `water.fs` now carries `u`, nothing else in the shader code changed. `src/shader_source_test.odin` scans every `.vs` and `.fs` under `data/shaders` (the data directory through `test_data_directory`, as the font and model tests do) and tests the scanner on its own lines; a run of number characters that starts with `.` (as `.5`) counts as a float, like the maximal run rule says. Verified here: `./build.sh check`, `./build.sh check-windows` and `./build.sh test` pass, and with `>> 8` put back into `water.fs` the test fails naming `data/shaders/water.fs:116` and the literal `8`, then passes again after the restore. The release build on the couch and the phone are for the user. Constructs Gladio might also mangle: none found in the shaders. Every line with an `ivec3` variable (`uvec3(cell)`) has no float variable, and `ivec3(floor(...))` is a constructor call, which `implicitConvertIntToFloat` skips as a function name. `implicitConvertFunctionParams`, which runs just before it, was not read in full, so a problem there is not ruled out.
