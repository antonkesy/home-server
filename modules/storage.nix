{
  lib,
  pkgs,
  settings,
  ...
}:

let
  inherit (settings) storage;

  dirs = map (name: "${storage.root}/${name}") storage.dirs;

  # everything that writes into the tree; same shape as gen-secrets (modules/secrets.nix)
  consumers = [
    "paperless-storage-dirs.service"
    "nextcloud-external-storage.service"
    "nextcloud-media-scan.service"
    "nextcloud-media-watch.service"
    "lab-backup.service"
  ];

  # mdmon crashes without a MAILADDR or PROGRAM; there is no MTA here
  alert = pkgs.writeShellScript "mdadm-alert" ''
    exec ${lib.getExe' pkgs.systemd "systemd-cat"} -t mdadm -p warning \
      ${lib.getExe' pkgs.coreutils "echo"} "$@"
  '';
in
{
  # assembles by homehost, so no ARRAY line: the array is named `lab:storage`
  boot.swraid.enable = true;
  boot.swraid.mdadmConf = ''
    PROGRAM ${alert}
  '';

  # by label, so this holds before the array exists. mkDefault yields to the
  # by-uuid entry `just hardware` would record once it is mounted
  fileSystems.${storage.root} = {
    device = lib.mkDefault "/dev/disk/by-label/${storage.label}";
    fsType = lib.mkDefault "ext4";
    # nofail keeps a lost array out of emergency mode
    options = [
      "noatime"
      "nofail"
    ];
  };

  # RequiresMountsFor, not tmpfiles: the mount is nofail, and tmpfiles would
  # build the whole tree on the SSD instead
  systemd.services.storage-dirs = {
    description = "create the shared directories on the storage array";
    wantedBy = [ "multi-user.target" ];
    # requiredBy too: the on-demand units start outside multi-user.target
    requiredBy = consumers;
    before = consumers;
    unitConfig.RequiresMountsFor = [ storage.root ];
    path = [ pkgs.acl ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # setgid plus a default ACL: ext4 has no file_mode=, so without this a file
    # nextcloud writes under umask 022 is unwritable by ak and the other way round
    script = ''
      set -euo pipefail

      install -d -o ${settings.user} -g ${settings.group} -m 2775 \
        ${lib.escapeShellArgs dirs}
      setfacl -m d:g::rwX -m g::rwX ${lib.escapeShellArgs dirs}
    '';
  };

  # mdadm ships mdcheck_start.timer, but its mdcheck script is not packaged
  systemd.services.mdraid-scrub = {
    description = "read-check every md array";
    path = [ pkgs.coreutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      # a resyncing or non-redundant array rejects the write; not an error
      for md in /sys/block/md*/md; do
        [ -w "$md/sync_action" ] || continue
        if echo check > "$md/sync_action"; then
          echo "scrubbing $md"
        else
          echo "skipping $md: busy or not redundant"
        fi
      done
    '';
  };

  systemd.timers.mdraid-scrub = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = storage.scrubOnCalendar;
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  # a mirror that degrades unnoticed is no mirror; warnings go to wall and the journal
  services.smartd = {
    enable = true;
    autodetect = true;
  };
}
