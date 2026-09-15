{ config, pkgs, ... }:

{
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # Intel QuickSync offload, so transcoding does not peg the CPU. Still has to
  # be switched on in Jellyfin: Dashboard > Playback > Hardware acceleration.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # VAAPI, Broadwell and newer
      vpl-gpu-rt # QSV via oneVPL
    ];
  };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
  ];
}
