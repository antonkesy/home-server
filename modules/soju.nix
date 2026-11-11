{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  scfg = settings.soju;
  inherit (settings) domain;
  host = "${scfg.subdomain}.${domain}";
  stateDir = "/var/lib/soju";
  adminPass = "${stateDir}/admin-pass";
  # the module's RuntimeDirectory, where its admin socket is too
  httpSocket = "/run/soju/http.sock";
  # modules/proxy.nix's wildcard; until the token is there, its self-signed
  # stand-in at the same path
  certDir = config.security.acme.certs.${domain}.directory;
  sojuctl = "${lib.getExe' config.services.soju.package "sojuctl"} --config ${config.services.soju.configFile}";
in
{
  # not in settings.subdomains: that list is the web uis behind nginx, and
  # this is plain irc over tls, straight to soju
  networking.hosts.${settings.lan.address} = [ host ];

  services.soju = {
    enable = true;
    hostName = host;
    listen = [
      "ircs://:${toString settings.ports.soju}"
      # for the start page's dot only (modules/overview.nix): plain http that
      # nginx can ask, where the ircs port speaks no http
      "http+unix://${httpSocket}"
    ];
    tlsCertificate = "${certDir}/fullchain.pem";
    tlsCertificateKey = "${certDir}/key.pem";
  };

  # a fixed user instead of the module's DynamicUser: the state is then a
  # plain /var/lib/soju for the backup, and the user can be in the
  # certificate's group
  users.users.soju = {
    isSystemUser = true;
    group = "soju";
    extraGroups = [ config.services.nginx.group ];
  };
  users.groups.soju = { };
  # soju makes its http socket 0775, so the group is what lets nginx in. a
  # worker picks the group up on its next start, i.e. the reboot an update is
  users.users.${config.services.nginx.user}.extraGroups = [ "soju" ];

  systemd.services.soju = {
    wants = [ "acme-${domain}.service" ];
    after = [ "acme-${domain}.service" ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "soju";
      Group = "soju";
    };
  };

  # soju re-reads the certificate on SIGHUP, which is its reload
  security.acme.certs.${domain}.reloadServices = [ "soju.service" ];

  # the bouncer account and the libera network, over the admin socket. both
  # are only created when missing; a password or nick changed through
  # BouncerServ later is not put back
  systemd.services.soju-setup = {
    description = "create the soju user and its networks";
    wantedBy = [ "multi-user.target" ];
    requires = [ "soju.service" ];
    after = [ "soju.service" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "2min";
    };
    script = ''
      set -euo pipefail

      # the admin socket is up shortly after the process
      for _ in $(seq 60); do
        ${sojuctl} user status >/dev/null 2>&1 && break
        sleep 1
      done

      # "already exists" is the second run; anything else fails the unit
      try() {
        local out
        out=$("$@" 2>&1) && { echo "$out"; return 0; }
        case "$out" in
          *"already exists"*) echo "$out" ;;
          *) echo "$out" >&2; return 1 ;;
        esac
      }

      try ${sojuctl} user create -username ${lib.escapeShellArg settings.user} \
        -password "$(cat ${adminPass})" -admin
      ${lib.concatMapStrings (n: ''
        try ${sojuctl} user run ${lib.escapeShellArg settings.user} network create \
          -name ${lib.escapeShellArg n.name} -addr ${lib.escapeShellArg n.addr} -nick ${lib.escapeShellArg n.nick}
      '') scfg.networks}
    '';
  };
}
