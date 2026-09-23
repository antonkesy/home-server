{
  config,
  lib,
  settings,
  ...
}:

let
  stateDir = "/var/lib/pihole";
  inherit (settings) lan ports upstreamDns;
  uid = toString config.users.users.${settings.user}.uid;
in
{
  virtualisation.podman.enable = true;

  # the host itself: a dead container must not take SSH and rollback with it
  networking.nameservers = upstreamDns;

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 ${uid} ${uid} -"
    "d ${stateDir}/etc-dnsmasq.d 0755 ${uid} ${uid} -"
  ];

  virtualisation.oci-containers.containers.pihole = {
    image = "pihole/pihole:2025.11.1";

    # v6 dropped the v5 names (WEBPASSWORD, PIHOLE_DNS_, ...); set here = read-only in the web UI
    environment = {
      TZ = config.time.timeZone;
      FTLCONF_dns_upstreams = lib.concatStringsSep ";" upstreamDns;
      # fritz.box is a real public domain: LAN names and reverse lookups go to the router
      FTLCONF_dns_revServers = "true,${lan.subnet},${lan.router},${lan.domain}";
      FTLCONF_dns_listeningMode = "all";
      FTLCONF_misc_etc_dnsmasq_d = "true";
      PIHOLE_UID = uid;
      PIHOLE_GID = uid;
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

  # the container copies /etc/hosts at start
  systemd.services.podman-pihole.restartTriggers = [ config.environment.etc.hosts.source ];
}
