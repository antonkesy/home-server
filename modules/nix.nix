{ ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.settings.trusted-users = [
    "root"
    "@wheel"
  ];

  # sunday jobs, spaced out, ahead of the 05:30 backup
  nix.gc = {
    automatic = true;
    dates = "Sun 03:15";
    randomizedDelaySec = "20min";
    options = "--delete-older-than 30d";
  };

  # scheduled, not auto-optimise-store: no per-build cost
  nix.optimise.automatic = true;
  nix.optimise.dates = [ "Sun 04:00" ];
}
