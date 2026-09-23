{ pkgs, ... }:

{
  # the port is in settings.ports, which networking.nix opens; jellyfin itself
  # reads it from /var/lib/jellyfin/config/network.xml, not from nix
  services.jellyfin.enable = true;

  # client auto-discovery; it never answered while the service was on demand
  networking.firewall.allowedUDPPorts = [
    1900
    7359
  ];

  # QSV; enable in Dashboard > Playback
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
  ];
}
