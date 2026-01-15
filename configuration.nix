{ config, pkgs, ... }:

let
  # Realtek r8125 2.5G Ethernet driver
  r8125 = config.boot.kernelPackages.callPackage ({ stdenv, lib, kernel, fetchFromGitHub }:
    stdenv.mkDerivation rec {
      pname = "r8125";
      version = "9.015.00";

      src = fetchFromGitHub {
        owner = "antonkesy";
        repo = "r8125";
        rev = "80c1b25847c996d3b92a92d1ac6856b0c5dff4b6";
        hash = "sha256-5P5FLT9rV6MdHlp9xKj0Zyb1Q2fajZu7h9YPRdxnWOw=";
      };

      sourceRoot = "source/src";
      hardeningDisable = [ "pic" "format" ];
      nativeBuildInputs = kernel.moduleBuildDependencies;

      makeFlags = [
        "KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      ];

      installPhase = ''
        mkdir -p $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/ethernet/realtek
        cp r8125.ko $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/ethernet/realtek/
      '';

      meta = with lib; {
        description = "Realtek RTL8125 2.5 Gigabit Ethernet driver";
        homepage = "https://github.com/antonkesy/r8125";
        license = licenses.gpl2Only;
        platforms = platforms.linux;
        maintainers = [];
      };
    }) {};
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  # System configuration
  system.stateVersion = "24.11";

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Realtek r8125 network driver
  boot.extraModulePackages = [ r8125 ];
  boot.kernelModules = [ "r8125" ];

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
    cifs-utils
    git
    vim
    htop
    curl
    wget
  ];

  # SSH Server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
    openFirewall = true;
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
  services.blueman.enable = true;

  # Create media directories and credentials
  systemd.tmpfiles.rules = [
    "d /mnt/music 0755 root root -"
    "d /mnt/movies 0755 root root -"
    "d /mnt/books 0755 root root -"
    "d /var/lib/kavita 0755 kavita kavita -"
  ];

  # NAS mounts
  fileSystems."/mnt/music" = {
    device = "//akstorage0/music";
    fsType = "cifs";
    options = [ 
      "credentials=/etc/smb-credentials"
      "iocharset=utf8"
      "vers=3.0"
      "uid=1000"
      "gid=1000"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
    ];
  };

  fileSystems."/mnt/movies" = {
    device = "//akstorage0/movies";
    fsType = "cifs";
    options = [ 
      "credentials=/etc/smb-credentials"
      "iocharset=utf8"
      "vers=3.0"
      "uid=1000"
      "gid=1000"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
    ];
  };

  fileSystems."/mnt/books" = {
    device = "//akstorage0/ebooks";
    fsType = "cifs";
    options = [ 
      "credentials=/etc/smb-credentials"
      "iocharset=utf8"
      "vers=3.0"
      "uid=1000"
      "gid=1000"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
    ];
  };

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
