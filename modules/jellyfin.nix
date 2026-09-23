{ config, pkgs, ... }:

{
  # reachable through the on-demand proxy only (modules/on-demand.nix); the
  # firewall stays shut on 8096 so a direct hit cannot bypass the idle
  # tracking, and the discovery ports it would open (1900+7359/udp) are of
  # no use for a server that is off most of the time
  services.jellyfin = {
    enable = true;
    openFirewall = false;
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
