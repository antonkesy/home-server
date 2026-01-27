{ config, pkgs, ... }:

{
  virtualisation.podman.enable = true;

  # Create persistence directories
  systemd.tmpfiles.rules = [
    "d /var/lib/pihole 0755 1000 1000 -"
    "d /var/lib/pihole/etc-pihole 0755 1000 1000 -"
    "d /var/lib/pihole/etc-dnsmasq.d 0755 1000 1000 -"
  ];

  services.resolved.enable = true;
  services.resolved.dnssec = "false";
  services.resolved.fallbackDns = [ "1.1.1.1" "8.8.8.8" ];
  
  # Alternative: If you want to use resolvconf instead
  # networking.resolvconf.enable = true;
  # services.resolved.enable = false;

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
      "--dns=127.0.0.1"
      "--dns=1.1.1.1"
    ];
  };

  systemd.services.configure-dns-after-pihole = {
    description = "Configure DNS to use Pi-hole after it starts";
    after = [ "podman-pihole.service" ];
    requires = [ "podman-pihole.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Wait for Pi-hole to be ready
      sleep 10
      
      # Point to Pi-hole for DNS
      echo "nameserver 127.0.0.1" > /etc/resolv.conf
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
      
      # If using resolved
      ${pkgs.systemd}/bin/resolvconf -u || true
    '';
  };
}
