# raylib binding and library

The Odin binding for raylib 6.0 with a raylib built from source, used through the `shared` collection (`build.sh` passes `-collection:shared=shared`, the game imports `shared:raylib` and `shared:raylib/rlgl`). Work item 0085.

Why a copy: the binding names its library by a path next to itself (`linux/libraylib.a`, and `../linux/libraylib.a` in `rlgl`), so no linker flag can swap in another archive. The toolchain under `~/opt/odin` stays untouched.

- `raylib.odin`, `raymath.odin`, `rlgl/rlgl.odin`, `LICENSE`: copied unchanged from `vendor/raylib/` of Odin release dev-2026-09 (nightly a2fb372). `raymath.odin` belongs to package `raylib` and the game uses it. `easings.odin` and `raygui.odin` (which needs its own `libraygui.a`) are not copied.
- `platform.odin`: ours. Declares GLFW's `glfwGetPlatform`, `glfwGetCurrentContext` and `glfwGetWindowSize` from the same archive, which the binding does not expose.
- `linux/libraylib.a`: written by `tools/build_raylib.sh`, GLFW with both the Wayland and the X11 backend. It is committed, so a checkout builds without cmake or a container.

After an Odin upgrade: copy `raylib.odin`, `raymath.odin`, `rlgl/rlgl.odin` and `LICENSE` from the new `vendor/raylib/` again, check the raylib version it binds, and when the version changed set `raylib_tag` in `tools/build_raylib.sh` and rerun it. The nix flake patches the three `.odin` files to link the system raylib and GLFW, so a renamed foreign import line breaks its `substituteInPlace` loudly.

## Build record

Rewritten by `tools/build_raylib.sh` below the marker.

<!-- build record -->
- raylib tag: 6.0 (https://github.com/raysan5/raylib), commit dbc56a87da87d973a9c5baa4e7438a9d20121d28
- cmake flags: -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF -DPLATFORM=Desktop -DGLFW_BUILD_WAYLAND=ON -DGLFW_BUILD_X11=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
- compiler: cc (GCC) 16.2.1 20260819 (Red Hat 16.2.1-2)
- built: 2026-09-28T16:24Z
- archive: linux/libraylib.a, 3390886 bytes
