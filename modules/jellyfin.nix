{ pkgs, ... }:

{
  # no openFirewall: 8096 stays closed, the on-demand proxy is the only way in
  services.jellyfin.enable = true;

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
