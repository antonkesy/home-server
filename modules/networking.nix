{ config, pkgs, ... }:

{
  networking.hostName = "lab";

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
