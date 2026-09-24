{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  port = settings.ports.nextcloud;
  storage = settings.storage.root;
  host = config.networking.hostName;
  occ = lib.getExe config.services.nextcloud.occ;
  ncfg = settings.nextcloud;

  # a previewDir that is not also a mount would never be backfilled by anything
  unknownPreviewDirs = lib.subtractLists settings.storage.dirs ncfg.previewDirs;

  # previewgenerator intersects these with the powers of four it derives from
  # preview_max_x/y (64, 256, 1024 here), so anything else in the list is
  # silently dropped. 256 is what the file list and the memories grid ask for;
  # the 2048 "max" preview nextcloud caches alongside it is the one that costs
  previewSizes = {
    squareSizes = "256";
    widthSizes = "256";
    heightSizes = "256";
  };

  # app config lives in the database, so re-asserted before every run, the way
  # the mounts are
  assertSizes = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      key: value: "${occ} config:app:set previewgenerator ${key} --value=${lib.escapeShellArg value}"
    ) previewSizes
  );

  # previews go to /var/lib/nextcloud on the SSD, and the run that would fill it
  # is exactly the one that must not happen. an ExecCondition makes systemd mark
  # the unit skipped rather than failed, so the next run still tries
  freeSpace = pkgs.writeShellScript "nextcloud-preview-free-space" ''
    free=$(${lib.getExe' pkgs.coreutils "df"} --output=avail --block-size=1G / \
      | ${lib.getExe' pkgs.coreutils "tail"} -n1 \
      | ${lib.getExe' pkgs.coreutils "tr"} -dc '0-9')
    if [ "$free" -lt ${toString ncfg.previewMinFreeGB} ]; then
      echo "only ''${free}G free on /, below ${toString ncfg.previewMinFreeGB}G - skipping"
      exit 1
    fi
  '';

  # OC\Preview\Movie needs ffmpeg; the module puts it on no unit's path
  previewTools = [ pkgs.ffmpeg-headless ];

  # nextcloud folder -> directory on the storage array (modules/storage.nix),
  # as "Local" external storage; the whole tree, lab's own backups included
  mounts = lib.genAttrs settings.storage.dirs (name: "${storage}/${name}");

  # `mount_id_of <name>` and `scan <name>` over one files_external:list call
  mountIdFn = ''
    mounts_json=$(${occ} files_external:list --output=json)
    mount_id_of() {
      jq -r --arg m "/$1" '.[] | select(.mount_point == $m) | .mount_id' <<<"$mounts_json"
    }
    # a directory added to settings.nix but not mounted yet is reported, not
    # failed: the unit that creates it runs first on the next boot
    scan() {
      local id
      id=$(mount_id_of "$1")
      [ -n "$id" ] || { echo "no mount for $1"; return 0; }
      ${occ} files_external:scan "$id"
    }
    option() {
      local id
      id=$(mount_id_of "$1")
      [ -n "$id" ] || { echo "no mount for $1"; return 0; }
      ${occ} files_external:option "$id" "$2" "$3"
    }
  '';

  forEachMount = f: lib.concatStringsSep "\n" (lib.mapAttrsToList f mounts);

  # `/<user>/files/<dir>` for every user and every previewDir; previewgenerator
  # reads the user back out of the path, so no account name is written down here
  forEachPreviewPath = ''
    paths=()
    while read -r uid; do
      ${lib.concatMapStringsSep "\n" (dir: ''paths+=("--path=/$uid/files/${dir}")'') ncfg.previewDirs}
    done < <(${occ} user:list --output=json | jq -r 'keys[]')
  '';

  # shared by the two preview units. both read originals off the array and write
  # thumbnails to /var/lib/nextcloud, so neither needs a UMask - nothing of
  # theirs lands on the array
  previewService = {
    after = [ "nextcloud-external-storage.service" ];
    unitConfig.RequiresMountsFor = [ settings.storage.root ];
    path = previewTools ++ (with pkgs; [ jq ]);
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      # both must pass; either one failing is a skip, not an error
      ExecCondition = [
        "${occ} status --exit-code"
        "${freeSpace}"
      ];
      # the array is asleep most of the time and neither run is urgent
      Nice = 10;
      IOSchedulingClass = "idle";
      # a first pass over a photo tree outlives anything shorter
      TimeoutStartSec = "12h";
    };
  };

  # shared by the scan-one and scan-all units below. ordering only: a `wants`
  # would re-run the (oneshot, not RemainAfterExit) external-storage unit on
  # every single scan, and multi-user.target pulls it in at boot anyway
  scanService = {
    after = [ "nextcloud-external-storage.service" ];
    unitConfig.RequiresMountsFor = [ settings.storage.root ];
    path = with pkgs; [ jq ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      ExecCondition = "${occ} status --exit-code";
      # a first scan of 3.6 T outlives the 90s default
      TimeoutStartSec = "30min";
    };
  };
in
{
  assertions = [
    {
      assertion = unknownPreviewDirs == [ ];
      message = "settings.nextcloud.previewDirs: not in storage.dirs: ${lib.concatStringsSep ", " unknownPreviewDirs}";
    }
  ];

  services.nextcloud = {
    enable = true;
    # one major version per upgrade
    package = pkgs.nextcloud34;
    hostName = host;
    config = {
      # seeds the install; rotate with `just set-nextcloud-pw`
      adminpassFile = "/var/lib/nextcloud/admin-pass";
      # sqlite would park every request behind an occ files:scan
      dbtype = "pgsql";
    };
    # peer auth over the unix socket; also orders setup after postgresql.target
    database.createLocally = true;
    settings = {
      overwriteprotocol = "http";
      # without the port, links point at :80
      overwritehost = "${host}:${toString port}";
      default_phone_region = settings.phoneRegion;
      # cron would otherwise walk the external storages every 15 minutes and
      # keep the disks awake; nextcloud-media-watch sees real changes already
      files_no_background_scan = true;
      # UTC hour for the heavy daily jobs
      maintenance_window_start = 4;
      # the module adds hostName
      trusted_domains = [
        "localhost"
        settings.lan.address
        "${host}.${settings.lan.domain}"
      ];

      # upstream's imaginary list has no video provider
      enabledPreviewProviders = [
        "OC\\Preview\\Imaginary"
        "OC\\Preview\\ImaginaryPDF"
        # heic/heif comes with imaginary (libvips), so no OC\Preview\HEIC
        "OC\\Preview\\Movie"
        "OC\\Preview\\Krita"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\TXT"
        "OC\\Preview\\OpenDocument"
      ];
      # default 4096; nothing here has a 4k display
      preview_max_x = 2048;
      preview_max_y = 2048;
      jpeg_quality = 60;
      # MB per preview job
      preview_max_memory = 512;

      # the php-fpm pool sets env[PATH] itself, so a worker never sees
      # systemd.services.phpfpm-nextcloud.path and OC\Preview\Movie finds no
      # ffmpeg on the web request path. nextcloud takes ffprobe from beside it
      preview_ffmpeg_path = lib.getExe pkgs.ffmpeg-headless;

      # memories. the nixpkgs package patches its own exiftool, ffmpeg, ffprobe
      # and go-vod paths into the app and refuses to let anything set them, so
      # nothing below names a binary

      # upstream: 1, i.e. the cron job walks every external storage - 3.6 T of
      # video - for five minutes every quarter hour, which is the one thing
      # files_no_background_scan exists to prevent. 2 is the timeline only
      "memories.index.mode" = "2";
      # ';' separated; the same directories the previews are built for
      "memories.timeline.default_path" = lib.concatMapStringsSep ";" (d: "/${d}") ncfg.previewDirs;

      # upstream: true, i.e. videos are served as they lie. go-vod is started by
      # a php-fpm worker and inherits that unit's devices, which is what the
      # serviceConfig below is for
      "memories.vod.disable" = false;
      # QSV, the driver stack jellyfin already pulls in (modules/jellyfin.nix)
      "memories.vod.vaapi" = true;
      # php-fpm runs with PrivateTmp, so the default under /tmp is a different
      # directory per unit and is thrown away on every restart. these hold the
      # copies memories makes of its own binaries, and go-vod's segments
      "memories.vod.tempdir" = "/var/cache/nextcloud-go-vod";
      "memories.exiftool.tmp" = "/var/cache/nextcloud-memories";
    };
    maxUploadSize = "4G";

    # resizes out of process; previewgenerator (below) then builds the
    # thumbnails for settings.nextcloud.previewDirs before a browser asks
    imaginary.enable = true;

    # keep in step with `package` above
    extraApps = {
      inherit (pkgs.nextcloud34Packages.apps) previewgenerator memories;
    };
    # extraApps on its own switches the app store off; the apps installed by
    # hand from it - and kept in the backup - are still wanted
    appstoreEnable = true;

    # upstream's sizes are below what nextcloud 34 needs; an overflowing opcache recompiles per request
    phpOptions = {
      # upstream: maxUploadSize, i.e. 4G per worker on a swapless box. uploads are
      # chunked and streamed by nginx, so one preview job is the real cap
      memory_limit = lib.mkForce "1G";
      "opcache.interned_strings_buffer" = "32";
      "opcache.max_accelerated_files" = "25000";
      "opcache.memory_consumption" = "256";
      # the store is read-only
      "opcache.revalidate_freq" = "60";
    };
  };

  # the array is group-writable by setgid + default ACL (modules/storage.nix);
  # render/video are the QSV nodes go-vod transcodes on, same as jellyfin
  users.users.nextcloud.extraGroups = [
    settings.group
    "render"
    "video"
  ];

  # upstream: :80, which would not match overwritehost
  services.nginx.virtualHosts.${host}.listen = [
    {
      addr = "0.0.0.0";
      port = port;
    }
  ];

  systemd.services.phpfpm-nextcloud.path = previewTools;
  systemd.services.nextcloud-cron.path = previewTools;

  # 0002 like paperless (modules/paperless.nix): what nextcloud writes to the
  # array stays writable for ak and the other services. its own state dir is
  # 0750 nextcloud:nextcloud, so nothing there is loosened
  systemd.services.nextcloud-cron.serviceConfig.UMask = "0002";

  # the php-fpm unit itself runs as root - only the pool runs as nextcloud - so
  # a CacheDirectory= here would be root-owned and the workers could not write
  # in it
  systemd.tmpfiles.rules = [
    "d /var/cache/nextcloud-go-vod 0750 nextcloud nextcloud -"
    "d /var/cache/nextcloud-memories 0750 nextcloud nextcloud -"
  ];

  systemd.services.phpfpm-nextcloud.serviceConfig = {
    UMask = "0002";
    # memories starts go-vod as a child of a php-fpm worker, so the render node
    # has to be reachable from this unit rather than from one of ours. upstream
    # phpfpm sets PrivateDevices, which hides /dev/dri entirely
    PrivateDevices = lib.mkForce false;
    DeviceAllow = [ "/dev/dri/renderD128 rw" ];
  };

  # a file share only; app state lives in the database, so re-asserted every boot
  systemd.services.nextcloud-disable-apps = {
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      # skips while uninstalled or in maintenance mode
      ExecCondition = "${occ} status --exit-code";
    };
    script = ''
      set -euo pipefail

      # apps already off or missing are reported, not failed
      ${occ} app:disable \
        activity app_api circles comments contactsinteraction dashboard \
        federation files_reminders firstrunwizard nextcloud_announcements \
        photos recommendations related_resources support survey_client \
        systemtags user_status weather_status
    '';
  };

  # upstream: 5m
  systemd.timers.nextcloud-cron.timerConfig.OnUnitActiveSec = lib.mkForce "15m";

  # previewgenerator queues only what nextcloud itself wrote (NodeWrittenEvent),
  # i.e. web and WebDAV uploads. a file that arrived on the array and was picked
  # up by a scan never enters that queue, so this is the cheap top-up and
  # nextcloud-preview-generate below is what actually covers the array
  systemd.services.nextcloud-preview-pregenerate = previewService // {
    description = "build the queued nextcloud previews";
    script = ''
      set -euo pipefail

      ${assertSizes}

      ${occ} preview:pre-generate
    '';
  };

  systemd.timers.nextcloud-preview-pregenerate = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      # one catch-up run after downtime, not one per missed hour
      Persistent = true;
      RandomizedDelaySec = "5min";
      Unit = "nextcloud-preview-pregenerate.service";
    };
  };

  # the array side: everything in previewDirs, however it got there. hours on
  # the first pass, minutes once the thumbnails exist - a file that already has
  # one is skipped. `just warm-previews` is the same unit by hand
  systemd.services.nextcloud-preview-generate = previewService // {
    description = "build the missing previews for the photo directories";
    script = ''
      set -euo pipefail

      ${assertSizes}

      df -h /

      ${forEachPreviewPath}

      ${occ} preview:generate-all -vv "''${paths[@]}"

      df -h /
    '';
  };

  systemd.timers.nextcloud-preview-generate = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = ncfg.previewOnCalendar;
      Persistent = true;
      RandomizedDelaySec = "20min";
      Unit = "nextcloud-preview-generate.service";
    };
  };

  # memories indexes on its own from nextcloud-cron, five minutes per run and
  # scoped to the timeline by memories.index.mode; what it is slowest at is the
  # first pass over a library that was already on the array - `just index-photos`
  systemd.services.nextcloud-memories-index = {
    description = "index the photo directories for memories";
    after = [ "nextcloud-external-storage.service" ];
    unitConfig.RequiresMountsFor = [ settings.storage.root ];
    path = with pkgs; [ jq ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      ExecCondition = "${occ} status --exit-code";
      Nice = 10;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "12h";
    };
    script = ''
      set -euo pipefail

      # memories takes one --path per run, relative to the user's own root -
      # unlike previewgenerator, which wants /<user>/files/<dir>
      while read -r uid; do
      ${lib.concatMapStringsSep "\n  " (
        dir: ''${occ} memories:index --user "$uid" --path ${lib.escapeShellArg "/${dir}"}''
      ) ncfg.previewDirs}
      done < <(${occ} user:list --output=json | jq -r 'keys[]')
    '';
  };

  # external mounts live in the database, so reconciled on every boot
  systemd.services.nextcloud-external-storage = {
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-setup.service" ];
    path = with pkgs; [ jq ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      ExecCondition = "${occ} status --exit-code";
    };
    script = ''
      set -euo pipefail

      ${occ} app:enable files_external
      ${mountIdFn}

      ${forEachMount (
        name: mount: ''
          if [ -z "$(mount_id_of ${name})" ]; then
            ${occ} files_external:create ${lib.escapeShellArg "/${name}"} local null::null \
              --config datadir=${lib.escapeShellArg mount}
          fi
        ''
      )}

      # the snapshot predates whatever was just created
      mounts_json=$(${occ} files_external:list --output=json)

      # upstream: 0, i.e. nextcloud trusts its index and never looks again. 1
      # re-checks the directory you open, which is what makes a file that
      # arrived past the watcher show up at all. re-asserted, not created-with:
      # an existing mount would never get it otherwise
      ${forEachMount (name: _: "option ${name} filesystem_check_changes 1")}
    '';
  };

  # one mount, started by the watcher below for the tree that changed
  systemd.services."nextcloud-media-scan@" = scanService // {
    description = "index one external storage";
    scriptArgs = "%i";
    script = ''
      set -euo pipefail

      ${mountIdFn}

      scan "$1"
    '';
  };

  # every mount: `just scan`, and once at boot for whatever changed while the
  # watch was down
  systemd.services.nextcloud-media-scan = scanService // {
    description = "index every external storage";
    wantedBy = [ "multi-user.target" ];
    script = ''
      set -euo pipefail

      ${mountIdFn}

      # one bad mount must not cost the others their scan
      ${forEachMount (name: _: ''scan ${name} || echo "scan of ${name} failed"'')}
    '';
  };

  # lab is the only writer now, so this sees everything; `just scan` is the repair
  # path for a tree changed while the watch was down
  systemd.services.nextcloud-media-watch = {
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-external-storage.service" ];
    unitConfig.RequiresMountsFor = [ settings.storage.root ];
    path = with pkgs; [ inotify-tools ];
    serviceConfig = {
      # inotifywait exits if a watched directory goes away with the array
      Restart = "always";
      RestartSec = "1min";
    };
    script = ''
      set -euo pipefail

      known=${lib.escapeShellArg " ${lib.concatStringsSep " " (lib.attrNames mounts)} "}
      declare -A pending

      # an event names a file; the scan takes the mount it sits in
      note() {
        local rel top
        rel=''${1#${storage}/}
        top=''${rel%%/*}
        case "$known" in *" $top "*) pending[$top]=1 ;; esac
      }

      # @path prunes paperless' consume dir: it churns on every document eaten,
      # while media/ underneath is exactly what has to be indexed
      inotifywait --monitor --recursive --quiet --format '%w%f' \
        --event close_write --event create --event delete \
        --event moved_to --event moved_from \
        ${lib.escapeShellArgs (lib.attrValues mounts ++ [ "@${settings.paperless.dir}/consume" ])} |
      while read -r changed; do
        note "$changed"
        # collapse a burst, then scan every mount it touched
        while read -r -t 10 more; do note "$more"; done
        for name in "''${!pending[@]}"; do
          echo "changed: $name"
          systemctl start --no-block "nextcloud-media-scan@$name.service"
        done
        pending=()
      done
    '';
  };
}
