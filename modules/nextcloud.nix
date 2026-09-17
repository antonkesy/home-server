{
  config,
  lib,
  pkgs,
  ...
}:

let
  port = 8080;
  host = config.networking.hostName;
  occ = lib.getExe config.services.nextcloud.occ;

  # occ paths (<user>/files/<dir>) mapped to the mount they live on; the two
  # cannot be derived from each other - one is logical, one is the watched tree
  scanPaths = {
    "ak/files/Shows" = "/mnt/nas/Shows";
    "ak/files/Movies" = "/mnt/nas/Movies";
    "ak/files/Music" = "/mnt/nas/Music";
    "ak/files/NAS" = "/mnt/nas/ak";
  };
in
{
  services.nextcloud = {
    enable = true;
    # one major version per upgrade; 33 only after 32 has migrated
    package = pkgs.nextcloud33;
    hostName = host;
    config = {
      # seeds the initial install only; afterwards `just set-nextcloud-pw`
      adminpassFile = "/var/lib/nextcloud/admin-pass";
      dbtype = "sqlite";
    };
    settings = {
      overwriteprotocol = "http";
      # without the port, links point at :80
      overwritehost = "${host}:${toString port}";
      default_phone_region = "DE";
      trusted_domains = [ "localhost" ];
    };
    https = false;
    maxUploadSize = "4G";
  };

  # the module's vhost defaults to :80
  services.nginx.virtualHosts.${host}.listen = [
    {
      addr = "0.0.0.0";
      inherit port;
    }
  ];

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
      # a deep scan over NFSv3 outlives the 90s default start timeout
      TimeoutStartSec = "30min";
    };
    # sqlite and a setup-only adminpass mean occ needs no runtime credentials,
    # so unlike the upstream occ units this one needs no LoadCredential
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
