{
  description = "Handy - A free, open source, offline speech-to-text application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    handy = {
      url = "github:cjpais/Handy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      handy,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      wrapHandy =
        pkgs: handy-pkg:
        pkgs.symlinkJoin {
          name = "handy-wrapped";
          paths = [ handy-pkg ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/handy \
              --prefix PATH : "${
                pkgs.lib.makeBinPath [
                  pkgs.xdotool
                  pkgs.wtype
                ]
              }"
          '';
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          wrapped = wrapHandy nixpkgs.legacyPackages.${system} handy.packages.${system}.default;
        in
        {
          default = wrapped;
          handy = wrapped;
        }
      );

      overlays.default = final: prev: {
        handy = wrapHandy final handy.packages.${final.system}.default;
      };

      homeManagerModules = {
        handy = import ./home-manager-module.nix;
        default = self.homeManagerModules.handy;
      };
    };
}
