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

  # occ paths (<user>/files/<dir>) mapped to the mount they live on; the two
  # cannot be derived from each other - one is logical, one is the watched tree
  scanPaths = {
    "ak/files/Shows" = "${nas}/Shows";
    "ak/files/Movies" = "${nas}/Movies";
    "ak/files/Music" = "${nas}/Music";
    "ak/files/NAS" = "${nas}/ak";
  };
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

  # the module's vhost defaults to :80
  services.nginx.virtualHosts.${host}.listen = [
    {
      addr = "0.0.0.0";
      inherit port;
    }
  ];

  systemd.services.phpfpm-nextcloud.path = previewTools;
  systemd.services.nextcloud-cron.path = previewTools;

  # nextcloud only indexes what it wrote itself; anything else on the share
  # stays invisible until a scan walks the tree. never timed - it is started
  # by nextcloud-media-watch below, or by hand via `just scan`
  systemd.services.nextcloud-media-scan = {
    after = [ "nextcloud-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      # the guard the module puts on nextcloud-cron: skip while nextcloud is
      # uninstalled or in maintenance mode rather than scan mid-upgrade
      ExecCondition = "${occ} status --exit-code";
      # a deep scan over SMB outlives the 90s default start timeout
      TimeoutStartSec = "30min";
    };
    # a setup-only adminpass and a database reached over peer auth mean occ
    # needs no runtime credentials, so unlike the upstream occ units this one
    # has no LoadCredential
    script = ''
      set -euo pipefail

      # the ls triggers the automount; with soft and mount-timeout=10s an
      # absent NAS errors out instead of hanging, so it is skipped not failed
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (occPath: mount: ''
          if timeout 15 ls ${lib.escapeShellArg mount} >/dev/null 2>&1; then
            ${occ} files:scan --path=${lib.escapeShellArg occPath}
          else
            echo "skipping ${occPath}: ${mount} unreachable"
          fi
        '') scanPaths
      )}
    '';
  };

  # inotify only reports writes this kernel performed, so this catches
  # everything written through lab and nothing written on the NAS itself -
  # for those, `just scan`. holding the watches also pins the automounts
  systemd.services.nextcloud-media-watch = {
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-setup.service" ];
    path = with pkgs; [ inotify-tools ];
    serviceConfig = {
      # the shares are automounts: a sleeping NAS fails the watch instead of
      # blocking it, so keep retrying rather than giving up until a rebuild
      Restart = "always";
      RestartSec = "1min";
    };
    script = ''
      set -euo pipefail

      inotifywait --monitor --recursive --quiet --format '%w%f' \
        --event close_write --event create --event delete \
        --event moved_to --event moved_from \
        ${lib.escapeShellArgs (lib.attrValues scanPaths)} |
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
