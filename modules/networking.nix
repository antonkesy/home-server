{ config, pkgs, ... }:

{
  networking.hostName = "lab";

  # Inbound ports, in one place. Services that set `openFirewall = true` also
  # open their own: ssh (22) and home-assistant (8123) are repeated below for
  # documentation, and jellyfin additionally opens 8920/tcp plus 1900+7359/udp
  # for DLNA discovery, which is why those are not listed here.
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
