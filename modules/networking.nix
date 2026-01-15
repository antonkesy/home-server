{ config, pkgs, ... }:

{
  networking.hostName = "home-server";
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 
    53      # DNS
    80      # HTTP
    443     # HTTPS
    5000    # Kavita
    8080    # Nextcloud
    8096    # Jellyfin
    8123    # Home Assistant
  ];
  networking.firewall.allowedUDPPorts = [ 
    53      # DNS
  ];
}
