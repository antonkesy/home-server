{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  stateDir = "/var/lib/pihole";
  inherit (settings) lan ports upstreamDns;
  uid = toString config.users.users.${settings.user}.uid;
  domains = pkgs.writeText "pihole-domains.json" (builtins.toJSON settings.pihole.domains);
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

  # domain lists live in gravity.db; added through the API, existing ones skipped
  systemd.services.pihole-domains = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "podman-pihole.service" ];
    after = [ "podman-pihole.service" ];
    restartTriggers = [ domains ];
    path = with pkgs; [
      coreutils
      curl
      jq
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      api=http://127.0.0.1:${toString ports.pihole}/api

      # FTL needs a moment after the container is up
      curl -s --retry 30 --retry-delay 2 --retry-all-errors -o /dev/null "$api/auth"

      pw=$(cut -d= -f2- ${stateDir}/pihole.env)
      sid=$(curl -sf -X POST -H 'content-type: application/json' \
        --data "$(jq -n --arg p "$pw" '{password: $p}')" "$api/auth" | jq -r .session.sid)
      trap 'curl -sf -X DELETE -H "sid: $sid" "$api/auth" >/dev/null || true' EXIT

      have=$(curl -sf -H "sid: $sid" "$api/domains" | jq -c '[.domains[] | {domain, type, kind}]')
      jq -c '.[]' ${domains} | while read -r entry; do
        jq -e --argjson e "$entry" \
          'any(.domain == $e.domain and .type == $e.type and .kind == $e.kind)' <<<"$have" >/dev/null && continue
        curl -sf -X POST -H "sid: $sid" -H 'content-type: application/json' \
          --data "$(jq -c '{domain, comment, groups: [0], enabled: true}' <<<"$entry")" \
          "$api/domains/$(jq -r .type <<<"$entry")/$(jq -r .kind <<<"$entry")" >/dev/null
        echo "added $(jq -r '"\(.type)/\(.kind) \(.domain)"' <<<"$entry")"
      done
    '';
  };
}
