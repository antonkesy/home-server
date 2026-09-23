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
  }
]
