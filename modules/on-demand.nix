{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

# a .socket owns the public port; the first connection starts
# systemd-socket-proxyd, which Requires the backend. proxyd exits after
# idleTimeout without a connection and the StopWhenUnneeded backend follows
let
  inherit (settings) onDemand;

  proxyd = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd";

  proxy =
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
        };
      };
    };

  # Type=simple is "active" before the port is open; any http answer will do
  waitFor =
    port: path:
    "${lib.getExe pkgs.curl} -s --retry 120 --retry-delay 1 --retry-max-time 240 --retry-all-errors -o /dev/null http://127.0.0.1:${toString port}${path}";

  # the wait above outlives short start timeouts (jellyfin: TimeoutSec=15 upstream)
  readyAfter = post: {
    TimeoutStartSec = "5min";
    ExecStartPost = post;
  };
in
lib.mkMerge [
  (proxy {
    name = "jellyfin";
    publicPort = settings.ports.jellyfin;
    backendPort = onDemand.jellyfinPort;
    backend = "jellyfin.service";
  })
  (proxy {
    name = "paperless";
    publicPort = settings.ports.paperless;
    backendPort = onDemand.paperlessPort;
    # upstream's anchor: Wants the other three, web+consumer BindsTo it
    backend = "paperless-scheduler.service";
  })
  (proxy {
    name = "nextcloud";
    publicPort = settings.ports.nextcloud;
    backendPort = onDemand.nextcloudPort;
    # postgres, redis, cron and the media watcher stay up: cheap, and occ needs them
    backend = "nginx.service";
  })
  {
    systemd.services.jellyfin = {
      # upstream: multi-user.target
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
      serviceConfig = readyAfter (waitFor onDemand.jellyfinPort "/health");
    };

    systemd.services.paperless-scheduler = {
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
    };
    # only Wanted by the scheduler, not bound to it
    systemd.services.paperless-task-queue.unitConfig.StopWhenUnneeded = true;
    systemd.services.paperless-web.serviceConfig = readyAfter (waitFor onDemand.paperlessPort "/");
    # granian must be listening before the first connection is forwarded
    systemd.services.paperless-proxy.after = [ "paperless-web.service" ];

    systemd.services.nginx = {
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
      serviceConfig = readyAfter (waitFor onDemand.nextcloudPort "/");
    };
    systemd.services.phpfpm-nextcloud = {
      # upstream: phpfpm.target
      wantedBy = lib.mkForce [ ];
      partOf = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
    };
    systemd.services.imaginary = {
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
    };
    systemd.services.nextcloud-proxy = {
      requires = [ "phpfpm-nextcloud.service" ];
      # only needed once a preview is asked for
      wants = [ "imaginary.service" ];
      after = [
        "phpfpm-nextcloud.service"
        "imaginary.service"
      ];
    };
  }
]
