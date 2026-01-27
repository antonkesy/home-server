{ config, pkgs, ... }:

{
  # Pi-hole DNS ad blocker
  services.pihole-ftl = {
    enable = true;
    settings = {
      misc.privacylevel = 0;
      upstreams = [
        "https://one.one.one.one/dns-query"
        "https://dns.google/dns-query"
      ];
      webserver.api.cli_pw = true; # Enable for lists management
    };
    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        enabled = true;
        description = "StevenBlack hosts";
      }
    ];
    openFirewallDNS = true;
  };

  services.pihole-web = {
    enable = true;
    ports = [ 80 ];
  };

  # Disable systemd-resolved for DNS compatibility
  services.resolved.enable = false;
}
