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
    in
    {
      packages = forAllSystems (system: {
        default = handy.packages.${system}.default;
        handy = handy.packages.${system}.handy;
      });

      overlays.default = final: prev: {
        handy = handy.packages.${final.system}.default;
      };

      homeManagerModules = {
        handy = import ./home-manager-module.nix;
        default = self.homeManagerModules.handy;
      };
    };
}
