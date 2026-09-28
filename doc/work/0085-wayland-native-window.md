# 0085 A Wayland native window at the panel's full size

Status: todo
Milestone: M11

## Goal

On a scaled Wayland desktop the game gets the scaled screen through XWayland (0084). A raylib built with GLFW's Wayland backend opens a native window, and with the high DPI flag its framebuffer is the panel's full size under a fractional scale, so a 2880 by 1920 laptop panel renders 2880 by 1920 without any desktop setting. Decision needed from the user before this starts: it adds a raylib build step to the toolchain.

## Deliverables

- A raylib 6.0 static library built from the upstream tag with both GLFW backends (`-DGLFW_BUILD_WAYLAND=ON -DGLFW_BUILD_X11=ON`; GLFW 3.4 picks Wayland at run time when the session offers it and falls back to X11), by `tools/build_raylib.sh` (fetches the tag, needs cmake, the Wayland, xkbcommon and libdecor headers; on Bazzite inside a distrobox), placed under `lib/linux/` and linked by `build.sh` in place of the vendored library through the linker shim directory. The nix flake already links nixpkgs raylib with an external nixpkgs GLFW that has both backends, so CI covers the Wayland build path once the game asks for it.
- `FLAG_WINDOW_HIGHDPI` at window creation, so the framebuffer follows the panel under a fractional scale (GLFW 3.4's fractional scale support on Wayland). The UI lays out in render pixels: `pixels_per_unit` and the pointer come from `GetRenderWidth` and `GetRenderHeight`, raylib's 2D scale matrix is accounted for (or bypassed) so text rasterises at the panel's pixel size and stays crisp, the screenshot command reads the render size, the display settings report the render size and the Resolution row lists the panel's modes as raylib reports them under Wayland.
- Windowed mode under Wayland needs libdecor for decorations; Borderless and Fullscreen do not. The launcher's SDL override is unaffected.
- Tests: the render pixel layout at scale 1 and 1.7 in the UI audit, the pointer mapping, the settings round trip.
- Docs: `doc/build.md` (the build step and the distrobox recipe), `doc/architecture.md`, `doc/ui.md`, `doc/log/<date>.md`, this item.

## Verify

- Builds and tests pass; CI's nix build links the external GLFW.
- User: the laptop shows 2880 by 1920 in Borderless and the text is crisp.
