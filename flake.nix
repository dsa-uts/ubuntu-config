{
  description = "Ubuntu system configuration for the dsa-dev k3s VM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    system-manager = {
      url = "github:numtide/system-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      system-manager,
      ...
    }:
    let
      linuxSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      hostSystems = linuxSystems ++ [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllHosts = nixpkgs.lib.genAttrs hostSystems;
    in
    {
      systemConfigs = nixpkgs.lib.genAttrs linuxSystems (system: {
        default = system-manager.lib.makeSystemConfig {
          modules = [
            { nixpkgs.hostPlatform = system; }
            ./modules/system.nix
          ];
        };
      });

      devShells = forAllHosts (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.go-task
              pkgs.nushell
            ]
            ++ nixpkgs.lib.optional (builtins.elem system linuxSystems) system-manager.packages.${system}.default;
          };
        }
      );
    };
}
