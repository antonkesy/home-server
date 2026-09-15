{ config, pkgs, ... }:

{
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # QSV; still has to be switched on in Dashboard > Playback
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
