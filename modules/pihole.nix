{
  config,
  lib,
  settings,
  ...
}:

let
  stateDir = "/var/lib/pihole";
  inherit (settings) lan ports upstreamDns;
in
{
  virtualisation.podman.enable = true;

  # Pi-hole owns :53
  services.resolved.enable = false;

  # public DNS on the host, so a dead container still leaves SSH + rollback working
  networking.nameservers = upstreamDns;

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
      FTLCONF_dns_upstreams = lib.concatStringsSep ";" upstreamDns;
      # fritz.box is a real public domain - without this, LAN names and reverse
      # lookups would be asked of the internet instead of the router
      FTLCONF_dns_revServers = "true,${lan.subnet},${lan.router},${lan.domain}";
      FTLCONF_dns_listeningMode = "all";
      FTLCONF_misc_etc_dnsmasq_d = "true";
      PIHOLE_UID = "1000";
      PIHOLE_GID = "1000";
    };

    # FTLCONF_webserver_api_password, from gen-secrets
    environmentFiles = [ "${stateDir}/pihole.env" ];

    volumes = [
      "${stateDir}:/etc/pihole"
      "${stateDir}/etc-dnsmasq.d:/etc/dnsmasq.d"
    ];

    ports = [
      "${toString ports.dns}:53/tcp"
      "${toString ports.dns}:53/udp"
      "${toString ports.pihole}:80/tcp" # web UI
    ];

    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--dns=${lib.head upstreamDns}"
    ];
  };

  # the container copies /etc/hosts at start, so a changed host record has to
  # reach FTL somehow
  systemd.services.podman-pihole.restartTriggers = [ config.environment.etc.hosts.source ];
}
