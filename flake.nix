{
  description = "Mine oh Belowed, a voxel automation game in Odin and raylib";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems =
        function: nixpkgs.lib.genAttrs systems (system: function nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "mine-oh-belowed";
          version = "0.0.0";
          src = self;

          nativeBuildInputs = [ pkgs.odin ];
          # The nixpkgs Odin package patches vendor:raylib to link the system
          # raylib instead of the bundled static library, hence raylib here.
          buildInputs = [
            pkgs.raylib
            pkgs.sdl3
          ];

          buildPhase = ''
            runHook preBuild
            odin build src -out:mine-oh-belowed -o:speed -vet -strict-style
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
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.odin
            pkgs.raylib
            pkgs.sdl3
          ];
        };
      });

      checks = forAllSystems (pkgs: {
        build = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      });
    };
}
