{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

# jellyfin and paperless run only while someone is connected. a .socket unit
# owns the public port; the first connection starts systemd-socket-proxyd,
# which Requires the real service. proxyd exits after idleTimeout without a
# connection, and the service - StopWhenUnneeded, no longer wanted by
# multi-user.target - is stopped with it. the socket keeps listening, so the
# next connection starts the pair again
let
  inherit (settings) onDemand;

  proxyd = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd";

  onDemandProxy =
    {
      name,
      publicPort,
      backendPort,
      backend,
    }:
    {
      systemd.sockets."${name}-proxy" = {
        description = "on-demand entry for ${name}";
        wantedBy = [ "sockets.target" ];
        listenStreams = [ "0.0.0.0:${toString publicPort}" ];
      };
      systemd.services."${name}-proxy" = {
        description = "on-demand proxy for ${name}";
        requires = [ backend ];
        after = [ backend ];
        serviceConfig = {
          ExecStart = "${proxyd} --exit-idle-time=${onDemand.idleTimeout} 127.0.0.1:${toString backendPort}";
          DynamicUser = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
        };
      };
    };

  # Type=simple counts as active the moment the process forks; the proxy
  # would then forward the first connection into a port nobody listens on
  # yet and the client sees a reset instead of a short wait
  waitForUrl =
    url:
    "${lib.getExe pkgs.curl} -sf --retry 60 --retry-delay 1 --retry-all-errors -o /dev/null ${url}";
  # any http answer will do, a 503 from maintenance mode included
  waitForPort =
    port:
    "${lib.getExe pkgs.curl} -s --retry 60 --retry-delay 1 --retry-all-errors -o /dev/null http://127.0.0.1:${toString port}/";
in
lib.mkMerge [
  (onDemandProxy {
    name = "jellyfin";
    publicPort = settings.ports.jellyfin;
    backendPort = onDemand.jellyfinPort;
    backend = "jellyfin.service";
  })
  (onDemandProxy {
    name = "paperless";
    publicPort = settings.ports.paperless;
    backendPort = onDemand.paperlessPort;
    # upstream's anchor: it Wants web/consumer/task-queue, and web+consumer
    # BindsTo it, so the whole set follows it up and down
    backend = "paperless-scheduler.service";
  })
  (onDemandProxy {
    name = "nextcloud";
    publicPort = settings.ports.nextcloud;
    backendPort = onDemand.nextcloudPort;
    # nginx serves nothing else on this box. postgres, redis, the cron timer
    # and the media watcher stay up: they are cheap, and occ needs them
    backend = "nginx.service";
  })
  {
    systemd.services.jellyfin = {
      # upstream: multi-user.target
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
      serviceConfig.ExecStartPost = waitForUrl "http://127.0.0.1:${toString onDemand.jellyfinPort}/health";
    };

    systemd.services.paperless-scheduler = {
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
    };
    # only Wanted by the scheduler, not bound to it
    systemd.services.paperless-task-queue.unitConfig.StopWhenUnneeded = true;
    # / answers 302, which -f accepts
    systemd.services.paperless-web.serviceConfig.ExecStartPost =
      waitForUrl "http://127.0.0.1:${toString onDemand.paperlessPort}/";
    # Requires only orders the proxy after the scheduler; granian must be
    # listening before the first connection is forwarded
    systemd.services.paperless-proxy.after = [ "paperless-web.service" ];

    # nginx is Type=simple, so the same wait; php-fpm is Type=notify and
    # imaginary only matters once a preview is asked for
    systemd.services.nginx = {
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
      serviceConfig.ExecStartPost = waitForPort onDemand.nextcloudPort;
    };
    systemd.services.phpfpm-nextcloud = {
      # upstream: phpfpm.target
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
    };
    systemd.services.imaginary = {
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
    };
    systemd.services.nextcloud-proxy = {
      requires = [
        "phpfpm-nextcloud.service"
        "imaginary.service"
      ];
      after = [
        "phpfpm-nextcloud.service"
        "imaginary.service"
      ];
    };
  }
]
