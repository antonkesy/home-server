{
  lib,
  pkgs,
  settings,
  ...
}:

let
  inherit (settings) storage;

  # the root too: a directory ak creates there then inherits the ACL
  dirs = [ storage.root ] ++ map (name: "${storage.root}/${name}") storage.dirs;

  # everything that reads or writes the tree; same shape as gen-secrets (modules/secrets.nix)
  consumers = [
    # jellyfin reads only, but a library scan against an unmounted array
    # empties the library
    "jellyfin.service"
    "paperless-storage-dirs.service"
    "nextcloud-external-storage.service"
    "nextcloud-media-scan.service"
    "nextcloud-media-watch.service"
    "lab-backup.service"
  ];

  # hdparm -S: 1..240 are 5-second units, 241..251 are 30-minute ones
  standbyValue = 240 + storage.standbyMinutes / 30;

  standby = pkgs.writeShellScript "disk-standby" ''
    # a USB bridge often rejects the ATA standby timer; the enclosure's own
    # idle timer is then what matters, so this must not fail the udev event
    ${lib.getExe pkgs.hdparm} -S ${toString standbyValue} "$1" || true
  '';

  # mdmon crashes without a MAILADDR or PROGRAM; there is no MTA here
  alert = pkgs.writeShellScript "mdadm-alert" ''
    exec ${lib.getExe' pkgs.systemd "systemd-cat"} -t mdadm -p warning \
      ${lib.getExe' pkgs.coreutils "echo"} "$@"
  '';
in
{
  assertions = [
    {
      assertion =
        storage.standbyMinutes >= 30
        && storage.standbyMinutes <= 330
        && lib.mod storage.standbyMinutes 30 == 0;
      message = "storage.standbyMinutes must be a multiple of 30, from 30 to 330";
    }
  ];

  # by member, not by serial: re-applied whenever the enclosure re-enumerates
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="linux_raid_member", RUN+="${standby} /dev/%k"
  '';

  # assembles by homehost, so no ARRAY line: the array is named `lab:storage`
  boot.swraid.enable = true;
  boot.swraid.mdadmConf = ''
    PROGRAM ${alert}
  '';

  # mdadm 4.6 shells out to modprobe from the udev callout; udevd's PATH has no kmod,
  # so the array never assembled. also load it early so udev needs no modprobe
  systemd.services.systemd-udevd.path = [ pkgs.kmod ];
  boot.kernelModules = [
    "md_mod"
    "raid1"
  ];

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
    # requiredBy too: a consumer pulled in by something else still needs the tree
    requiredBy = consumers;
    before = consumers;
    unitConfig.RequiresMountsFor = [ storage.root ];
    path = [ pkgs.acl ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # setgid plus a default ACL: ext4 has no file_mode=, so without this a file
    # nextcloud writes under umask 022 is unwritable by ak and the other way round.
    # only these directories, not their contents - `just fix-perms` repairs a
    # tree that was copied in as root
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
    # -n standby,q: only check a disk that is already spinning, and stay quiet
    # about the skip, because the log line alone would wake it. replaces the
    # `-a` default, so that has to be repeated. autodetected inherits this
    defaults.monitored = "-a -n standby,q";
    # upstream polls every 1800s and there is no option for it
    extraOptions = [ "--interval=7200" ];
  };
}
