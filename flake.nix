{
  description = "Mine oh Belowed, a voxel automation game in Odin and raylib";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems =
        function: nixpkgs.lib.genAttrs systems (system: function nixpkgs.legacyPackages.${system});
      # nixpkgs deletes the bundled raylib libraries from Odin's vendor
      # directory and points vendor:raylib at the system raylib, but leaves
      # the rlgl sub package pointing at the deleted ../linux/libraylib.a.
      # Importing vendor:raylib/rlgl then fails to link. This override gives
      # rlgl the same treatment.
      odinForNix =
        pkgs:
        pkgs.odin.overrideAttrs (previous: {
          postPatch =
            (previous.postPatch or "")
            + ''
              substituteInPlace vendor/raylib/rlgl/rlgl.odin \
                --replace-fail '"../linux/libraylib.so.600" when RAYLIB_SHARED else "../linux/libraylib.a",' '"system:raylib",'
            '';
        });
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "mine-oh-belowed";
          version = "0.0.0";
          src = self;

          nativeBuildInputs = [ (odinForNix pkgs) ];
          # The nixpkgs Odin package patches vendor:raylib to link the system
          # raylib instead of the bundled static library, hence raylib here.
          # libX11 is for the rlgl sub package, see odinForNix.
          buildInputs = [
            pkgs.raylib
            pkgs.sdl3
            pkgs.xorg.libX11
          ];

          buildPhase = ''
            runHook preBuild
            odin build src -out:mine-oh-belowed -o:speed -vet -strict-style -define:BUILD_COMMIT=${self.shortRev or self.dirtyShortRev or "unknown"} -define:BUILD_TIME=${self.lastModifiedDate or "unknown"}
            runHook postBuild
          '';

          doCheck = true;
          checkPhase = ''
            runHook preCheck
            odin test src
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
            (odinForNix pkgs)
            pkgs.raylib
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
