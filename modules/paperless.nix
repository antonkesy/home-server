{
  lib,
  pkgs,
  settings,
  ...
}:

let
  inherit (settings) paperless;

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
    # only the on-demand proxy talks to it (modules/on-demand.nix)
    address = "127.0.0.1";
    port = settings.onDemand.paperlessPort;
    # from `just install`
    passwordFile = "/var/lib/paperless/admin-pass";
    # the documents live on the NAS; dataDir stays on the SSD - the database,
    # the search index and the secret key must not sit on a soft mount, and
    # they are what `just backup` covers
    consumptionDir = consume;
    mediaDir = media;
    settings = {
      PAPERLESS_OCR_LANGUAGE = settings.ocrLanguages;
      # 0 would mean inotify, which only reports writes this kernel performed -
      # a scan written to the share by the desktop or a scanner is invisible
      PAPERLESS_CONSUMER_POLLING_INTERVAL = paperless.pollInterval;
      PAPERLESS_CONSUMER_STABILITY_DELAY = paperless.stabilityDelay;
      # subfolders dropped into consume, and the tree `just import-legacy`
      # copies in, are ignored otherwise
      PAPERLESS_CONSUMER_RECURSIVE = true;
    };
  };

  # the mounts are forced to uid=ak gid=lab, dir_mode=0775, so a write from
  # paperless only lands if its user is in the group - chown/chmod do nothing
  # on cifs. inside the units `id -G` shows 65534 for the group, because
  # PrivateUsers=true maps it to nobody; the kernel still compares the real
  # gid, so the write works
  users.users.paperless.extraGroups = [ settings.group ];

  # the module would create these from systemd-tmpfiles, which runs in early
  # boot: every boot would walk into the automount and wait for the NAS, and
  # the chown it wants cannot succeed on cifs anyway. paperless-nas-dirs below
  # does it once the share is really there
  systemd.tmpfiles.settings."10-paperless".${consume} = lib.mkForce { };
  systemd.tmpfiles.settings."10-paperless".${media} = lib.mkForce { };

  # every paperless unit runs with ProtectSystem=strict and the two dirs in
  # ReadWritePaths, so a missing dir fails the unit while systemd sets up its
  # mount namespace - before any ExecStartPre could create it
  systemd.services.paperless-nas-dirs = {
    description = "create the paperless directories on the NAS share";
    requiredBy = units;
    before = units;
    # without this the unit runs seconds into boot and triggers a cifs mount
    # that fails with "Network is unreachable"
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # ordering only: RequiresMountsFor would fail the unit outright when the
    # NAS is asleep, which is the one case the retry below exists for
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

      # the ls triggers the automount; with soft and mount-timeout=10s an
      # absent NAS errors out instead of hanging, so keep asking for ~2 min in
      # case it is still waking up
      for _ in $(seq 8); do
        timeout 15 ls ${lib.escapeShellArg "${settings.nas.mountRoot}/ak"} >/dev/null 2>&1 && break || sleep 5
      done

      # autofs is mounted at the share path at all times, so `mountpoint` would
      # say yes with no cifs underneath - and mkdir would then quietly build
      # the tree on the SSD, hidden under the mount point
      findmnt -t cifs -M ${lib.escapeShellArg "${settings.nas.mountRoot}/ak"} >/dev/null

      mkdir -p ${lib.escapeShellArg consume} ${lib.escapeShellArg media}
    '';
  };

  # the module asks for RequiresMountsFor on all three ReadWritePaths, which
  # makes the scheduler - and through bindsTo the other three units - fail for
  # good when the boot's first mount attempt loses the race with the network,
  # since a failed mount job is never retried. paperless-nas-dirs is what
  # guarantees the share is really there, and it retries; same reasoning as the
  # "no RequiresMountsFor" note in modules/backup.nix
  systemd.services.paperless-scheduler.unitConfig.RequiresMountsFor = lib.mkForce [
    "/var/lib/paperless"
  ];

  # the consumer exits hard when the consume dir is missing; with the module's
  # Restart=on-failure and the default 100ms backoff, a brief NAS outage burns
  # the start limit and leaves it failed for good
  systemd.services.paperless-consumer.serviceConfig.RestartSec = "1min";
}
