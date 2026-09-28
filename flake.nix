{
  description = "Mine oh Belowed, a voxel automation game in Odin and raylib";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems =
        function: nixpkgs.lib.genAttrs systems (system: function nixpkgs.legacyPackages.${system});
      # The build stamp the game shows: the revision and the last modified
      # time, in one define with a space so Odin never reads it as a number.
      buildInfo =
        let
          date = self.lastModifiedDate or "00000000000000";
          part = start: length: builtins.substring start length date;
        in
        "${self.shortRev or self.dirtyShortRev or "unknown"} ${part 0 4}-${part 4 2}-${part 6 2}T${part 8 2}:${part 10 2}Z";
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "mine-oh-belowed";
          version = "0.0.0";
          src = self;

          nativeBuildInputs = [ pkgs.odin ];
          # The game imports the raylib binding from the repository's
          # shared collection (work item 0085), which links the
          # committed libraylib.a. Here it links the nixpkgs raylib instead,
          # which is built against an external GLFW with both the Wayland
          # and the X11 backend, and platform.odin's GLFW calls link that
          # GLFW. libX11 is in the binding's own import block.
          buildInputs = [
            pkgs.raylib
            pkgs.glfw
            pkgs.sdl3
            pkgs.xorg.libX11
          ];

          postPatch = ''
            substituteInPlace shared/raylib/raylib.odin \
              --replace-fail '"linux/libraylib.so.600" when RAYLIB_SHARED else "linux/libraylib.a",' '"system:raylib",'
            substituteInPlace shared/raylib/rlgl/rlgl.odin \
              --replace-fail '"../linux/libraylib.so.600" when RAYLIB_SHARED else "../linux/libraylib.a",' '"system:raylib",'
            substituteInPlace shared/raylib/platform.odin \
              --replace-fail 'foreign import lib "linux/libraylib.a"' 'foreign import lib "system:glfw"'
          '';

          buildPhase = ''
            runHook preBuild
            odin build src -out:mine-oh-belowed -collection:shared=shared -o:speed -vet -strict-style -define:BUILD_INFO="${buildInfo}"
            runHook postBuild
          '';

          doCheck = true;
          checkPhase = ''
            runHook preCheck
            odin test src -collection:shared=shared
            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 mine-oh-belowed $out/bin/mine-oh-belowed
            if [ -d data ]; then
              mkdir -p $out/share/mine-oh-belowed
              cp -r data $out/share/mine-oh-belowed/
            fi
            runHook postInstall
          '';

          meta = {
            description = "Voxel automation game, Minecraft's world with Factorio's loop";
            license = pkgs.lib.licenses.agpl3Only;
            mainProgram = "mine-oh-belowed";
          };
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.odin
            pkgs.raylib
            pkgs.glfw
            pkgs.sdl3
            pkgs.xorg.libX11
          ];
        };
      });

      checks = forAllSystems (pkgs: {
        build = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      });
    };
}
