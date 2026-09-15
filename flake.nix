{
  description = "Home Server NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      homeServer = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
      };
    in
    {
      nixosConfigurations = {
        home-server = homeServer;
        lab = homeServer; # hostName, for a bare `nixos-rebuild --flake .`
      };

      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system}.system = homeServer.config.system.build.toplevel;
    };
}
