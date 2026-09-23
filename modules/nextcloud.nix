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

  # OC\Preview\Movie needs ffmpeg; the module puts it on no unit's path
  previewTools = [ pkgs.ffmpeg-headless ];

  # nextcloud folder -> directory on the storage array (modules/storage.nix),
  # as "Local" external storage. backups/ is deliberately not among them
  mounts = {
    Shows = "${storage}/Shows";
    Movies = "${storage}/Movies";
    Music = "${storage}/Music";
    Documents = "${storage}/Documents";
  };

  # `mount_id_of <name>` from one files_external:list call
  mountIdFn = ''
    mounts_json=$(${occ} files_external:list --output=json)
    mount_id_of() {
      jq -r --arg m "/$1" '.[] | select(.mount_point == $m) | .mount_id' <<<"$mounts_json"
    }
  '';

  forEachMount = f: lib.concatStringsSep "\n" (lib.mapAttrsToList f mounts);
in
{
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
    };
    maxUploadSize = "4G";

    # resizes out of process; previews are still built on demand, pre-generating the media filled the SSD
    imaginary.enable = true;

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

  # the array is group-writable by setgid + default ACL (modules/storage.nix)
  users.users.nextcloud.extraGroups = [ settings.group ];

  # upstream: :80, which would not match overwritehost
  services.nginx.virtualHosts.${host}.listen = [
    {
      addr = "0.0.0.0";
      port = port;
    }
  ];

  systemd.services.phpfpm-nextcloud.path = previewTools;
  systemd.services.nextcloud-cron.path = previewTools;

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
    '';
  };

  # nextcloud only indexes what it wrote itself; started by the watcher below or `just scan`
  systemd.services.nextcloud-media-scan = {
    after = [ "nextcloud-external-storage.service" ];
    wants = [ "nextcloud-external-storage.service" ];
    unitConfig.RequiresMountsFor = [ settings.storage.root ];
    path = with pkgs; [ jq ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      ExecCondition = "${occ} status --exit-code";
      # a first scan of 3.6 T outlives the 90s default
      TimeoutStartSec = "30min";
    };
    script = ''
      set -euo pipefail

      ${mountIdFn}

      ${forEachMount (name: _: ''${occ} files_external:scan "$(mount_id_of ${name})"'')}
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

      # @path prunes paperless' tree: each consumed document would trigger a full scan
      inotifywait --monitor --recursive --quiet --format '%w%f' \
        --event close_write --event create --event delete \
        --event moved_to --event moved_from \
        ${lib.escapeShellArgs (lib.attrValues mounts ++ [ "@${settings.paperless.dir}" ])} |
      while read -r changed; do
        echo "changed: $changed"
        # collapse a burst into one scan
        while read -r -t 120 _; do :; done
        systemctl start --no-block nextcloud-media-scan.service
      done
    '';
  };
}
