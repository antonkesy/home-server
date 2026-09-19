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
      settings = import ./settings.nix;

      homeServer = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit settings; };
        modules = [ ./configuration.nix ];
      };
    in
    {
      nixosConfigurations = {
        home-server = homeServer;
        ${settings.hostName} = homeServer; # for a bare `nixos-rebuild --flake .`
      };

      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system}.system = homeServer.config.system.build.toplevel;
    };
}
