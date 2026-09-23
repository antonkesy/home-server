{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  cfg = settings.backup;

  # shellcheck runs at build time; site values arrive as env vars
  script =
    name:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gnutar
        pkgs.zstd
        pkgs.util-linux
        pkgs.findutils
        pkgs.diffutils
        config.services.postgresql.package
        config.services.nextcloud.occ
        config.systemd.package
      ];
      runtimeEnv = {
        LAB_HOST = config.networking.hostName;
        LAB_BACKUP_DIR = cfg.dir;
        LAB_BACKUP_KEEP = toString cfg.keep;
        LAB_NEXTCLOUD_VERSION = config.services.nextcloud.package.version;
        LAB_PG_VERSION = config.services.postgresql.package.version;
        LAB_STATE_VERSION = config.system.stateVersion;
      };
      text = builtins.readFile ../scripts/${name}.sh;
    };

  backup = script "lab-backup";
  restore = script "lab-restore";
in
{
  environment.systemPackages = [
    backup
    restore
  ];

  # built by CI, which is what runs shellcheck on the scripts
  system.build.lab-backup-scripts = pkgs.symlinkJoin {
    name = "lab-backup-scripts";
    paths = [
      backup
      restore
    ];
  };

  systemd.services.lab-backup = {
    description = "config and secrets snapshot to the storage array";
    unitConfig.RequiresMountsFor = [ settings.storage.root ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe backup;
    };
  };

  systemd.timers.lab-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = cfg.onCalendar;
      Persistent = true;
      RandomizedDelaySec = "20min";
    };
  };
}
