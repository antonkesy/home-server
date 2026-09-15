{
  config,
  lib,
  pkgs,
  ...
}:

let
  # static DHCP lease on the Fritz!Box
  lanAddress = "192.168.178.29";
in
{
  networking.hostName = "lab";

  # podman copies this file into the Pi-hole container, where FTL serves it to
  # the whole LAN - the NixOS default (127.0.0.2 lab) makes every client
  # resolve `lab` to its own loopback
  networking.hosts = {
    "127.0.0.2" = lib.mkForce [ ];
    "${lanAddress}" = [
      "lab"
      "lab.fritz.box"
    ];
  };

  # jellyfin's openFirewall also opens 8920/tcp and 1900+7359/udp
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    22 # SSH
    53 # Pi-hole DNS
    4000 # Pi-hole web UI
    8080 # Nextcloud
    8096 # Jellyfin
    8123 # Home Assistant
    28981 # Paperless-ngx
  ];
  networking.firewall.allowedUDPPorts = [
    53 # Pi-hole DNS
  ];
}
