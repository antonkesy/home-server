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

  names = [
    "paperless-consumer"
    "paperless-scheduler"
    "paperless-task-queue"
    "paperless-web"
  ];

  units = map (name: "${name}.service") names;
in
{
  services.paperless = {
    enable = true;
    # upstream binds 127.0.0.1 only
    address = "0.0.0.0";
    port = settings.ports.paperless;
    # from gen-secrets
    passwordFile = "/var/lib/paperless/admin-pass";
    # dataDir stays on the SSD: database, index and secret key have no business on the array
    consumptionDir = consume;
    mediaDir = media;
    settings = {
      PAPERLESS_OCR_LANGUAGE = settings.ocrLanguages;
      # a scan dropped into a subfolder of consume/ is ignored otherwise
      PAPERLESS_CONSUMER_RECURSIVE = true;
      # upstream: every sunday. it checksums every file on the array, so it
      # runs with the scrub instead, on the one night the disks are up anyway.
      # celery ANDs day-of-month with day-of-week: first saturday
      PAPERLESS_SANITY_TASK_CRON = "30 4 1-7 * 6";
      # upstream polls every 10 minutes; no mail accounts are configured
      PAPERLESS_EMAIL_TASK_CRON = "disable";
    };
  };

  # writes need the group. inside the units `id -G` shows 65534
  # (PrivateUsers), the kernel still compares the real gid
  users.users.paperless.extraGroups = [ settings.group ];

  # the array mount is nofail, so the module's tmpfiles would build the tree
  # on the SSD whenever it is missing; paperless-storage-dirs waits for the mount
  systemd.tmpfiles.settings."10-paperless".${consume} = lib.mkForce { };
  systemd.tmpfiles.settings."10-paperless".${media} = lib.mkForce { };

  # upstream leaves the state dir 0755, which the UMask below would fill with a
  # world-readable database and secret key. the directory is what keeps them in
  systemd.tmpfiles.settings."10-paperless"."/var/lib/paperless".d.mode = lib.mkForce "0700";
  systemd.tmpfiles.settings."10-paperless"."/var/lib/paperless/index".d.mode = lib.mkForce "0700";

  systemd.services = lib.mkMerge [
    # upstream: 0066, so a consumed document lands 0600 and nothing outside
    # paperless can read it - not ak, not nextcloud, which share the tree
    # through the group. paperless copies the mode along with the file, so the
    # default ACL alone does not cover this
    (lib.genAttrs names (_: {
      serviceConfig.UMask = lib.mkForce "0002";
    }))

    {
      # ProtectSystem=strict + ReadWritePaths: a missing dir fails the unit before any ExecStartPre
      paperless-storage-dirs = {
        description = "create the paperless directories on the storage array";
        requiredBy = units;
        before = units;
        unitConfig.RequiresMountsFor = [ paperless.dir ];
        path = [ pkgs.coreutils ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = settings.user;
          Group = settings.group;
        };
        script = ''
          set -euo pipefail

          mkdir -p ${lib.escapeShellArg consume} ${lib.escapeShellArg media}
        '';
      };

      # exits hard when the consume dir is missing; upstream's 100ms backoff would burn the start limit
      paperless-consumer.serviceConfig.RestartSec = "1min";
    }
  ];
}
