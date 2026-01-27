{ config, pkgs, ... }:

{
  # Pi-hole DNS ad blocker
  services.pihole-ftl = {
    enable = true;
    settings = {
      misc.privacylevel = 0;
      misc.readOnly = false;
      dns.dnssec = true; # Enable DNSSEC validation
      dns.ecs = true; # Enable EDNS Client Subnet
      upstreams = [
        "https://one.one.one.one/dns-query" # Cloudflare (DNSSEC)
        "https://dns.google/dns-query" # Google (ECS, DNSSEC)
        "1.1.1.1"
        "1.1.1.2"
      ];
      webserver.api.cli_pw = true; # Enable for lists management
    };
    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        enabled = true;
        description = "StevenBlack hosts";
      }
      {
        url = "https://adaway.org/hosts.txt";
        enabled = true;
        description = "AdAway hosts";
      }
      {
        url = "https://someonewhocares.org/hosts/zero/hosts";
        enabled = true;
        description = "Someone Who Cares hosts";
      }
      {
        url = "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext";
        enabled = true;
        description = "Peter Lowe's Ad and tracking server list";
      }
      {
        url = "https://raw.githubusercontent.com/blocklistproject/Lists/master/ads.txt";
        enabled = true;
        description = "Block List Project - Ads";
      }
      {
        url = "https://raw.githubusercontent.com/blocklistproject/Lists/master/tracking.txt";
        enabled = true;
        description = "Block List Project - Tracking";
      }
      {
        url = "https://raw.githubusercontent.com/blocklistproject/Lists/master/malware.txt";
        enabled = true;
        description = "Block List Project - Malware";
      }
      {
        url = "https://raw.githubusercontent.com/blocklistproject/Lists/master/phishing.txt";
        enabled = true;
        description = "Block List Project - Phishing";
      }
      {
        url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/multi.txt";
        enabled = true;
        description = "HaGeZi Multi PRO - Comprehensive ad/tracking/malware blocklist";
      }
      {
        url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/tif.txt";
        enabled = true;
        description = "HaGeZi Threat Intelligence Feeds - Malware, phishing, scam";
      }
      {
        url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/popupads.txt";
        enabled = true;
        description = "HaGeZi Pop-Up Ads - Blocks annoying pop-up ads";
      }
    ];
    openFirewallDNS = true;
  };

  services.pihole-web = {
    enable = true;
    ports = [ 4000 ];
  };

  # Disable systemd-resolved for DNS compatibility
  services.resolved.enable = false;
   
   # Ensure resolv.conf is usable
  networking.nameservers = [ "127.0.0.1" ];
}
