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
        # networking.hostName is "lab", so a bare `nixos-rebuild --flake .`
        # on the machine itself resolves without naming the attribute.
        lab = homeServer;
      };

      formatter.${system} = pkgs.nixfmt-tree;

      # `nix flake check` / `just check`: evaluates the whole system closure,
      # which catches option typos and renames without building anything.
      checks.${system}.system = homeServer.config.system.build.toplevel;
    };
}
