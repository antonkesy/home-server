{ config, pkgs, ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.settings.trusted-users = [
    "root"
    "@wheel"
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    randomizedDelaySec = "45min";
    persistent = true;
    options = "--delete-older-than 30d";
  };

  # scheduled, not auto-optimise-store: no per-build cost
  nix.optimise.automatic = true;
  nix.optimise.dates = [ "weekly" ];
}
