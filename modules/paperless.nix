{
  lib,
  pkgs,
  settings,
  ...
}:

let
  inherit (settings) paperless;

  share = "${settings.nas.mountRoot}/ak";
  consume = "${paperless.dir}/consume";
  media = "${paperless.dir}/media";

  units = [
    "paperless-consumer.service"
    "paperless-scheduler.service"
    "paperless-task-queue.service"
    "paperless-web.service"
  ];
in
{
  services.paperless = {
    enable = true;
    # loopback only; the on-demand proxy is the way in (modules/on-demand.nix)
    port = settings.onDemand.paperlessPort;
    # from gen-secrets
    passwordFile = "/var/lib/paperless/admin-pass";
    # dataDir stays on the SSD: database, index and secret key must not sit on a soft mount
    consumptionDir = consume;
    mediaDir = media;
    settings = {
      PAPERLESS_OCR_LANGUAGE = settings.ocrLanguages;
      # 0 = inotify, which cifs never fires for remote writes
      PAPERLESS_CONSUMER_POLLING_INTERVAL = paperless.pollInterval;
      PAPERLESS_CONSUMER_STABILITY_DELAY = paperless.stabilityDelay;
      # subfolders (and the `just import-legacy` tree) are ignored otherwise
      PAPERLESS_CONSUMER_RECURSIVE = true;
    };
  };

  # cifs: writes need the group. inside the units `id -G` shows 65534
  # (PrivateUsers), the kernel still compares the real gid
  users.users.paperless.extraGroups = [ settings.group ];

  # the module's tmpfiles run in early boot and would wait on the automount;
  # their chown cannot work on cifs anyway
  systemd.tmpfiles.settings."10-paperless".${consume} = lib.mkForce { };
  systemd.tmpfiles.settings."10-paperless".${media} = lib.mkForce { };

  # ProtectSystem=strict + ReadWritePaths: a missing dir fails the unit before any ExecStartPre
  systemd.services.paperless-nas-dirs = {
    description = "create the paperless directories on the NAS share";
    requiredBy = units;
    before = units;
    # otherwise it runs before the network is up and the cifs mount fails
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # ordering only: RequiresMountsFor would fail outright while the NAS wakes up
    unitConfig.WantsMountsFor = [ paperless.dir ];
    path = with pkgs; [
      coreutils
      util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      User = settings.user;
      Group = settings.group;
    };
    script = ''
      set -euo pipefail

      # the ls triggers the automount; soft + mount-timeout=10s errors out
      # instead of hanging, so retry ~2 min for a waking NAS
      for _ in $(seq 8); do
        timeout 15 ls ${lib.escapeShellArg share} >/dev/null 2>&1 && break || sleep 5
      done

      # autofs sits at the share path, so `mountpoint` says yes with no cifs
      # underneath and mkdir would build the tree on the SSD
      findmnt -t cifs -M ${lib.escapeShellArg share} >/dev/null

      mkdir -p ${lib.escapeShellArg consume} ${lib.escapeShellArg media}
    '';
  };

  # upstream: all three ReadWritePaths. a lost mount race at boot would fail the
  # scheduler for good (a failed mount job is never retried); paperless-nas-dirs retries
  systemd.services.paperless-scheduler.unitConfig.RequiresMountsFor = lib.mkForce [
    "/var/lib/paperless"
  ];

  # exits hard when the consume dir is missing; upstream's 100ms backoff would burn the start limit
  systemd.services.paperless-consumer.serviceConfig.RestartSec = "1min";
}
