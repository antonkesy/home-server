{ config, pkgs, ... }:

{
  virtualisation.podman.enable = true;

  # Create persistence directories
  systemd.tmpfiles.rules = [
    "d /var/lib/pihole 0755 1000 1000 -"
    "d /var/lib/pihole/etc-pihole 0755 1000 1000 -"
    "d /var/lib/pihole/etc-dnsmasq.d 0755 1000 1000 -"
  ];

  services.resolved.enable = false;
  services.resolved.dnssec = "false";
  services.resolved.fallbackDns = [ "1.1.1.1" "8.8.8.8" ];

  # Configure networking
  networking = {
    firewall = {
      enable = true;
      # Allow Pi-hole services (web UI exposed on host port 4000)
      allowedTCPPorts = [ 53 4000 443 ];
      allowedUDPPorts = [ 53 67 68 ];
    };
    
    # Use external DNS initially, will be overridden by Pi-hole
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
  };

  virtualisation.oci-containers.containers.pihole = {
    autoStart = true;
    image = "pihole/pihole:2025.11.1";

    environment = {
      TZ = "UTC";
      WEBPASSWORD = "";
      PIHOLE_UID = "1000";
      PIHOLE_GID = "1000";
      PIHOLE_DNS = "1.1.1.1;1.0.0.1";
      DNSMASQ_LISTENING = "all";
      IPv6 = "false";
      # Add this to prevent startup DNS issues
      REV_SERVER = "false";
      # Permit all origins for CORS
      CORS_ORIGIN = "*";
    };

    volumes = [
      "/var/lib/pihole:/etc/pihole"
      "/var/lib/pihole/etc-dnsmasq.d:/etc/dnsmasq.d"
    ];

    ports = [
      "53:53/tcp"    # Bind to localhost only
      "53:53/udp"    # Bind to localhost only
      "4000:80/tcp"           # Web UI (host:container)
    ];

    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--dns=1.1.1.1"
    ];
  };
}
