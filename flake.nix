{
  description = "NixOS configuration for the dsa k3s cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    {
      nixosConfigurations.nixos-dsa = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./hosts/nixos-dsa
          ./modules/k3s-server.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              users.k3s-admin = import ./home/k3s-admin.nix;
              users.mizokami = import ./home/mizokami.nix;
            };
          }
        ];
      };
    };
}
