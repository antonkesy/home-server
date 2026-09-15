{ config, pkgs, ... }:

let
  stateDir = "/var/lib/pihole";
in
{
  virtualisation.podman.enable = true;

  # Pi-hole owns :53
  services.resolved.enable = false;

  # public DNS on the host, so a dead container still leaves SSH + rollback working
  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
  ];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 1000 1000 -"
    "d ${stateDir}/etc-dnsmasq.d 0755 1000 1000 -"
  ];

  virtualisation.oci-containers.containers.pihole = {
    autoStart = true;
    image = "pihole/pihole:2025.11.1";

    # v6 removed the v5 names (WEBPASSWORD, PIHOLE_DNS_, DNSMASQ_LISTENING, ...)
    # rather than deprecating them. Values set here are read-only in the web UI.
    environment = {
      TZ = config.time.timeZone;
      FTLCONF_dns_upstreams = "1.1.1.1;1.0.0.1";
      # fritz.box is a real public domain - without this, LAN names and reverse
      # lookups would be asked of the internet instead of the router
      FTLCONF_dns_revServers = "true,192.168.178.0/24,192.168.178.1,fritz.box";
      FTLCONF_dns_listeningMode = "all";
      FTLCONF_misc_etc_dnsmasq_d = "true";
      PIHOLE_UID = "1000";
      PIHOLE_GID = "1000";
    };

    # FTLCONF_webserver_api_password, from `just install`
    environmentFiles = [ "${stateDir}/pihole.env" ];

    volumes = [
      "${stateDir}:/etc/pihole"
      "${stateDir}/etc-dnsmasq.d:/etc/dnsmasq.d"
    ];

    ports = [
      "53:53/tcp"
      "53:53/udp"
      "4000:80/tcp" # web UI
    ];

    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--dns=1.1.1.1"
    ];
  };

  # the container copies /etc/hosts at start, so a changed host record has to
  # reach FTL somehow
  systemd.services.podman-pihole.restartTriggers = [ config.environment.etc.hosts.source ];
}
