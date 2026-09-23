{
  description = "Home Server NixOS Configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
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
        ${settings.hostName} = homeServer; # bare `nixos-rebuild --flake .`
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;

      checks.${system}.system = homeServer.config.system.build.toplevel;
    };
}
