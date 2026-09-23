{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  port = settings.ports.nextcloud;
  nas = settings.nas.mountRoot;
  host = config.networking.hostName;
  occ = lib.getExe config.services.nextcloud.occ;

  # OC\Preview\Movie shells out to ffmpeg, which the nextcloud module puts on
  # no unit's path at all, so every unit that may generate a preview gets it
  previewTools = [ pkgs.ffmpeg-headless ];

  # nextcloud folder -> host mount from modules/nas.nix, exposed as a "Local"
  # external storage
  mounts = {
    Shows = "${nas}/Shows";
    Movies = "${nas}/Movies";
    Music = "${nas}/Music";
    NAS = "${nas}/ak";
  };

  mountId =
    name:
    ''$(${occ} files_external:list --output=json | jq '.[] | select(.mount_point == "/${name}") | .mount_id')'';
in
{
  services.nextcloud = {
    enable = true;
    # one major version per upgrade; 34 only after 33 has migrated
    package = pkgs.nextcloud34;
    hostName = host;
    config = {
      # seeds the initial install only; afterwards `just set-nextcloud-pw`
      adminpassFile = "/var/lib/nextcloud/admin-pass";
      # sqlite serialises every write in the instance, so one occ files:scan
      # over the NAS would park every browser request behind it
      dbtype = "pgsql";
    };
    # peer auth over the unix socket, so no runtime credentials; this also
    # orders nextcloud-setup after postgresql.target and defaults dbhost to
    # /run/postgresql, neither of which a hand-rolled services.postgresql does
    database.createLocally = true;
    settings = {
      overwriteprotocol = "http";
      # without the port, links point at :80
      overwritehost = "${host}:${toString port}";
      default_phone_region = settings.phoneRegion;
      trusted_domains = [ "localhost" ];

      # the module's list is fine until imaginary is on, at which point it
      # swaps in an imaginary-flavoured one - with no video provider. spell the
      # whole list out so Movies/Shows keep their thumbnails
      enabledPreviewProviders = [
        "OC\\Preview\\Imaginary"
        "OC\\Preview\\ImaginaryPDF"
        # libvips covers heic/heif through the imaginary provider, so no
        # separate OC\Preview\HEIC (which would want imagick + a heic delegate)
        "OC\\Preview\\Movie"
        "OC\\Preview\\Krita"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\TXT"
        "OC\\Preview\\OpenDocument"
      ];
      # nextcloud defaults to 4096: a quarter of the pixels is a quarter of the
      # bytes read back off the SSD, and nothing here has a 4k display
      preview_max_x = 2048;
      preview_max_y = 2048;
      jpeg_quality = 60;
      # MB per preview job; the cap that keeps one huge image off the box
      preview_max_memory = 512;
    };
    https = false;
    maxUploadSize = "4G";

    # a preview used to mean: decode and resize the original in PHP, per
    # request, per thumbnail. imaginary does the resizing out of process.
    # previews are still built on demand and cached under
    # data/appdata_*/preview - pre-generating the whole NAS ahead of time
    # filled the SSD
    imaginary.enable = true;

    # the module's defaults are below what nextcloud 34 needs - once the file
    # cache overflows php recompiles on every request and the whole UI drags
    phpOptions = {
      # maxUploadSize sets upload_max_filesize, post_max_size *and*
      # memory_limit, so a 4G upload cap asks for 4G per worker - times
      # pm.max_children = 120, on a box with no swap. uploads are chunked and
      # nginx streams them (fastcgi_request_buffering off), so no worker ever
      # holds a whole file; the cap only has to cover one preview job
      memory_limit = lib.mkForce "1G";
      "opcache.interned_strings_buffer" = "32";
      "opcache.max_accelerated_files" = "25000";
      "opcache.memory_consumption" = "256";
      # the store is read-only, so there is nothing to notice changing
      "opcache.revalidate_freq" = "60";
    };
  };

  # the mounts are forced to uid=ak gid=lab, dir_mode=0775, so a write from
  # nextcloud only lands if its user is in the group - chown/chmod do nothing
  # on cifs
  users.users.nextcloud.extraGroups = [ settings.group ];

  # the module's vhost defaults to :80; only the on-demand proxy talks to it
  # (modules/on-demand.nix), clients see `port`
  services.nginx.virtualHosts.${host}.listen = [
    {
      addr = "127.0.0.1";
      port = settings.onDemand.nextcloudPort;
    }
  ];

  systemd.services.phpfpm-nextcloud.path = previewTools;
  systemd.services.nextcloud-cron.path = previewTools;

  # the instance is a file share, nothing else; the stock apps below only add
  # background jobs, database churn and UI. app state lives in the database,
  # so it is reasserted on every boot like the external mounts. kept: files,
  # sharing, external storage, trashbin, versions, viewer, notifications,
  # share by mail, text, and everything nextcloud refuses to disable
  systemd.services.nextcloud-disable-apps = {
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      ExecCondition = "${occ} status --exit-code";
    };
    script = ''
      set -euo pipefail

      # apps that are already off or not installed are reported, not failed
      ${occ} app:disable \
        activity app_api circles comments contactsinteraction dashboard \
        federation files_reminders firstrunwizard nextcloud_announcements \
        photos recommendations related_resources support survey_client \
        systemtags user_status weather_status
    '';
  };

  # the module runs cron.php every 5 min; share expiry and trashbin cleanup
  # do not need to be that punctual
  systemd.timers.nextcloud-cron.timerConfig.OnUnitActiveSec = lib.mkForce "15m";

  # external mounts live in the database, so they are reconciled on every boot
  systemd.services.nextcloud-external-storage = {
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-setup.service" ];
    path = with pkgs; [ jq ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      # skip while uninstalled or in maintenance mode
      ExecCondition = "${occ} status --exit-code";
    };
    script = ''
      set -euo pipefail

      ${occ} app:enable files_external

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: mount: ''
          if [ -z "${mountId name}" ]; then
            ${occ} files_external:create ${lib.escapeShellArg "/${name}"} local null::null \
              --config datadir=${lib.escapeShellArg mount}
          fi
        '') mounts
      )}
    '';
  };

  # nextcloud only indexes what it wrote itself; anything else on the share
  # stays invisible until a scan walks the tree. never timed - it is started
  # by nextcloud-media-watch below, or by hand via `just scan`
  systemd.services.nextcloud-media-scan = {
    after = [ "nextcloud-external-storage.service" ];
    wants = [ "nextcloud-external-storage.service" ];
    path = with pkgs; [ jq ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      ExecCondition = "${occ} status --exit-code";
      # a deep scan over SMB outlives the 90s default start timeout
      TimeoutStartSec = "30min";
    };
    script = ''
      set -euo pipefail

      # the ls triggers the automount; with soft and mount-timeout=10s an
      # absent NAS errors out instead of hanging, so it is skipped not failed
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: mount: ''
          if timeout 15 ls ${lib.escapeShellArg mount} >/dev/null 2>&1; then
            ${occ} files_external:scan "${mountId name}"
          else
            echo "skipping ${name}: ${mount} unreachable"
          fi
        '') mounts
      )}
    '';
  };

  # inotify only reports writes this kernel performed, so this catches
  # everything written through lab and nothing written on the NAS itself -
  # for those, `just scan`. the watches do not pin the automounts - inotify
  # holds an inode, not a mount - it is the restart below that re-triggers them
  systemd.services.nextcloud-media-watch = {
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-external-storage.service" ];
    path = with pkgs; [ inotify-tools ];
    serviceConfig = {
      # the shares are automounts: a sleeping NAS fails the watch instead of
      # blocking it, so keep retrying rather than giving up until a rebuild
      Restart = "always";
      RestartSec = "1min";
    };
    script = ''
      set -euo pipefail

      # @path prunes a subtree from the recursive watch: paperless writes every
      # consumed document under there, and each write would otherwise trigger a
      # deep scan of every share. `just scan` still indexes it
      inotifywait --monitor --recursive --quiet --format '%w%f' \
        --event close_write --event create --event delete \
        --event moved_to --event moved_from \
        ${lib.escapeShellArgs (lib.attrValues mounts ++ [ "@${settings.paperless.dir}" ])} |
      while read -r changed; do
        echo "changed: $changed"
        # a copy fires thousands of events; collapse the whole burst into one
        # scan by waiting for the tree to go quiet first
        while read -r -t 120 _; do :; done
        systemctl start --no-block nextcloud-media-scan.service
      done
    '';
  };
}
