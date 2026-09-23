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
    # loopback only; the on-demand proxy is the way in (modules/on-demand.nix)
    port = settings.onDemand.paperlessPort;
    # from gen-secrets
    passwordFile = "/var/lib/paperless/admin-pass";
    # dataDir stays on the SSD: database, index and secret key have no business on the array
    consumptionDir = consume;
    mediaDir = media;
    settings = {
      PAPERLESS_OCR_LANGUAGE = settings.ocrLanguages;
      # subfolders (and the `just import-legacy` tree) are ignored otherwise
      PAPERLESS_CONSUMER_RECURSIVE = true;
    };
  };

  # writes need the group. inside the units `id -G` shows 65534
  # (PrivateUsers), the kernel still compares the real gid
  users.users.paperless.extraGroups = [ settings.group ];

  # the array mount is nofail, so the module's tmpfiles would build the tree
  # on the SSD whenever it is missing; paperless-storage-dirs waits for the mount
  systemd.tmpfiles.settings."10-paperless".${consume} = lib.mkForce { };
  systemd.tmpfiles.settings."10-paperless".${media} = lib.mkForce { };

  # ProtectSystem=strict + ReadWritePaths: a missing dir fails the unit before any ExecStartPre
  systemd.services.paperless-storage-dirs = {
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
  systemd.services.paperless-consumer.serviceConfig.RestartSec = "1min";
}
