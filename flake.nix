{
  description = "Home Server NixOS Configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # the scanner's web ui (modules/yass.nix)
  inputs.yass.url = "github:antonkesy/YASS";
  inputs.yass.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { nixpkgs, yass, ... }:
    let
      system = "x86_64-linux";
      settings = import ./settings.nix;

      homeServer = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit settings yass; };
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
