{ pkgs, settings, ... }:

{
  # the port is in settings.ports, which networking.nix opens; jellyfin itself
  # reads it from /var/lib/jellyfin/config/network.xml, not from nix
  services.jellyfin.enable = true;

  # client auto-discovery
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

  # render/video for QSV; the array is group-writable by setgid + default ACL
  # (modules/storage.nix), and jellyfin saves artwork next to the media
  users.users.jellyfin.extraGroups = [
    "render"
    "video"
    settings.group
  ];
}
