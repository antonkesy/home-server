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

  # Nobody logs into this box regularly, so the store has to clean up after
  # itself or it will silently fill the disk.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    randomizedDelaySec = "45min";
    persistent = true;
    options = "--delete-older-than 30d";
  };

  # Hardlink duplicate store paths on a schedule. Done here rather than via
  # auto-optimise-store so it does not add latency to every build.
  nix.optimise.automatic = true;
  nix.optimise.dates = [ "weekly" ];
}
