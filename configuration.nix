{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # System configuration
  system.stateVersion = "24.11";

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Networking
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

  # System packages
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    curl
    wget
  ];

  # Create media directories
  systemd.tmpfiles.rules = [
    "d /mnt/music 0755 root root -"
    "d /mnt/movies 0755 root root -"
    "d /mnt/books 0755 root root -"
    "d /var/lib/kavita 0755 kavita kavita -"
  ];

  # Home Assistant
  services.home-assistant = {
    enable = true;
    port = 8123;
    openFirewall = true;
    extraComponents = [
      "esphome"
      "met"
      "radio_browser"
    ];
    config = {
      default_config = {};
      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
        trusted_proxies = [ "127.0.0.1" "::1" ];
      };
    };
  };

  # Jellyfin media server
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # Nextcloud
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud30;
    hostName = "localhost";
    config = {
      adminpassFile = "/var/lib/nextcloud/admin-pass";
      dbtype = "sqlite";
    };
    settings = {
      overwriteprotocol = "http";
      default_phone_region = "US";
    };
    https = false;
  };

  # Pi-hole alternative using Blocky DNS
  services.blocky = {
    enable = true;
    settings = {
      ports = {
        dns = 53;
        http = 4000;
      };
      upstreams = {
        groups = {
          default = [
            "https://one.one.one.one/dns-query"
            "https://dns.google/dns-query"
          ];
        };
      };
      blocking = {
        blackLists = {
          ads = [
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
          ];
        };
        clientGroupsBlock = {
          default = [ "ads" ];
        };
      };
      caching = {
        minTime = "5m";
        maxTime = "30m";
        prefetching = true;
      };
    };
  };

  # Kavita reading server (using systemd service)
  systemd.services.kavita = {
    description = "Kavita Reading Server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    environment = {
      TZ = "Europe/Berlin";
      DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "true";
    };
    
    serviceConfig = {
      Type = "simple";
      User = "kavita";
      Group = "kavita";
      WorkingDirectory = "/var/lib/kavita";
      ExecStart = "${pkgs.kavita}/bin/kavita";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # Create kavita user
  users.users.kavita = {
    isSystemUser = true;
    group = "kavita";
    home = "/var/lib/kavita";
    createHome = true;
  };

  users.groups.kavita = {};

  # Disable systemd-resolved for DNS compatibility
  services.resolved.enable = false;

  # Users configuration
  users.users.homeserver = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    packages = with pkgs; [];
  };
}
