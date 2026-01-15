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
    53      # Pi-hole DNS
    80      # Nextcloud HTTP
    443     # Pi-hole HTTPS
    5000    # Kavita
    8080    # Nextcloud
    8096    # Jellyfin
    8123    # Home Assistant
    8181    # Pi-hole Web UI
    8443    # Nextcloud HTTPS
  ];
  networking.firewall.allowedUDPPorts = [ 
    53      # Pi-hole DNS
  ];

  # Enable Docker for containerized services
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Enable Docker Compose
  environment.systemPackages = with pkgs; [
    docker-compose
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
  ];

  # Home Assistant service
  systemd.services.home-assistant-docker = {
    description = "Home Assistant Docker Container";
    after = [ "docker.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/home-server/home-assistant";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      Restart = "on-failure";
    };
  };

  # Jellyfin service
  systemd.services.jellyfin-docker = {
    description = "Jellyfin Docker Container";
    after = [ "docker.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/home-server/jellyfin";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      Restart = "on-failure";
    };
  };

  # Kavita service
  systemd.services.kavita-docker = {
    description = "Kavita Docker Container";
    after = [ "docker.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/home-server/kavita";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      Restart = "on-failure";
    };
  };

  # Nextcloud service
  systemd.services.nextcloud-docker = {
    description = "Nextcloud Docker Container";
    after = [ "docker.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/home-server/nextcloud";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      Restart = "on-failure";
    };
  };

  # Pi-hole service
  systemd.services.pihole-docker = {
    description = "Pi-hole Docker Container";
    after = [ "docker.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/home-server/pihole";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      Restart = "on-failure";
    };
  };

  # Disable systemd-resolved for Pi-hole compatibility
  services.resolved.enable = false;

  # Users configuration (adjust as needed)
  users.users.homeserver = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    packages = with pkgs; [];
  };
}
