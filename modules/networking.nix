{ config, pkgs, ... }:

{
  networking.hostName = "lab";
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 
    22      # SSH
    53      # PiHole DNS
    80      # HTTP
    443     # HTTPS
    5000    # Kavita
    4000    # PiHole
    8080    # Nextcloud
    8096    # Jellyfin
    8123    # Home Assistant
  ];
  networking.firewall.allowedUDPPorts = [ 
    53      # PiHole DNS
  ];
}
