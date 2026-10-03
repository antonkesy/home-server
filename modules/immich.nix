{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  icfg = settings.immich;
  host = config.networking.hostName;
  port = settings.ports.immich;
  library = "${settings.storage.root}/${icfg.libraryDir}";
  mediaLocation = config.services.immich.mediaLocation;

  # the first account; also the owner of the external library
  adminEmail = settings.adminEmail;
  adminPass = "/var/lib/immich/admin-pass";

  api = "http://localhost:${toString port}/api";
in
{
  assertions = [
    {
      assertion = lib.elem icfg.libraryDir settings.storage.dirs;
      message = "settings.immich.libraryDir: ${icfg.libraryDir} is not in storage.dirs";
    }
    {
      assertion = lib.hasPrefix "${library}/" icfg.uploadDir;
      message = "settings.immich.uploadDir must sit inside ${library}";
    }
  ];

  services.immich = {
    enable = true;
    # upstream binds localhost only
    host = "";
    inherit port;

    # QSV, the driver stack jellyfin pulls in (modules/jellyfin.nix)
    accelerationDevices = [ "/dev/dri/renderD128" ];

    # a config file makes Administration > Settings read-only in the UI;
    # anything not named here keeps immich's default
    settings = {
      server.externalDomain = "http://${host}:${toString port}";

      # uploads: library/<storageLabel>/<year>/<month>/<original name>, i.e. a
      # tree nextcloud can browse. without this they stay under upload/ as uuids
      storageTemplate = {
        enabled = true;
        template = "{{y}}/{{MM}}/{{filename}}";
      };

      library = {
        # the nightly pass over the external library
        scan = {
          enabled = true;
          cronExpression = icfg.scanCron;
        };
        # inotify on the import paths; what makes a file copied onto the
        # array show up between scans
        watch.enabled = true;
      };

      ffmpeg = {
        accel = "qsv";
        accelDecode = true;
      };

      # lab-backup dumps the database (modules/backup.nix); upstream would
      # write a dump into mediaLocation/backups every night on top of that
      backup.database.enabled = false;
    };
  };

  # the array is group-writable by setgid + default ACL (modules/storage.nix);
  # render/video are the QSV nodes
  users.users.immich.extraGroups = [
    settings.group
    "render"
    "video"
  ];

  systemd.services.immich-server = {
    requires = [ "immich-storage-dirs.service" ];
    after = [ "immich-storage-dirs.service" ];
    unitConfig.RequiresMountsFor = [ library ];
    serviceConfig = {
      # uploads land on the array, everything else (thumbs, encoded video,
      # profile, upload staging) stays on the SSD. the unit has PrivateMounts,
      # and a missing source fails the start instead of filling the SSD
      BindPaths = [ "${icfg.uploadDir}:${mediaLocation}/library" ];
      # upstream: 0077, which would leave every upload unreadable for nextcloud.
      # the state dir itself stays 0700 through the module's tmpfiles rule
      UMask = lib.mkForce "0002";
    };
  };

  # the bind target has to exist on the host side too
  systemd.tmpfiles.rules = [
    "d ${mediaLocation}/library 0700 immich immich -"
  ];

  # the array mount is nofail; like paperless-storage-dirs, this waits for it
  # rather than letting a tree appear on the SSD
  systemd.services.immich-storage-dirs = {
    description = "create the immich upload directory on the storage array";
    unitConfig.RequiresMountsFor = [ library ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = settings.user;
      Group = settings.group;
    };
    script = ''
      set -euo pipefail

      mkdir -p ${lib.escapeShellArg icfg.uploadDir}
    '';
  };

  # admin account and external library live in the database, so reconciled
  # over the api on every boot - the counterpart of nextcloud-external-storage
  systemd.services.immich-setup = {
    description = "create the immich admin and the Photos external library";
    wantedBy = [ "multi-user.target" ];
    after = [ "immich-server.service" ];
    requires = [ "immich-server.service" ];
    path = with pkgs; [
      curl
      jq
    ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "5min";
    };
    script = ''
      set -euo pipefail

      api=${api}
      email=${lib.escapeShellArg adminEmail}
      password=$(cat ${adminPass})

      # Type=simple on the server: ready is when it answers
      for _ in $(seq 120); do
        curl -fsS "$api/server/ping" >/dev/null 2>&1 && break
        sleep 1
      done
      curl -fsS "$api/server/ping" >/dev/null

      # 400 once an admin exists; anything else is a real failure
      code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$api/auth/admin-sign-up" \
        -H 'Content-Type: application/json' \
        --data "$(jq -n --arg e "$email" --arg p "$password" --arg n ${lib.escapeShellArg settings.user} \
          '{email: $e, password: $p, name: $n}')")
      case "$code" in
        201) echo "created admin $email" ;;
        400) ;;
        *) echo "admin-sign-up returned $code" >&2; exit 1 ;;
      esac

      token=$(curl -fsS -X POST "$api/auth/login" \
        -H 'Content-Type: application/json' \
        --data "$(jq -n --arg e "$email" --arg p "$password" '{email: $e, password: $p}')" \
        | jq -r .accessToken)
      auth=(-H "Authorization: Bearer $token" -H 'Content-Type: application/json')

      me=$(curl -fsS "''${auth[@]}" "$api/users/me")
      uid=$(jq -r .id <<<"$me")

      # the per-user folder under library/ is the uuid unless a label is set
      if [ "$(jq -r .storageLabel <<<"$me")" != ${lib.escapeShellArg settings.user} ]; then
        curl -fsS -o /dev/null "''${auth[@]}" -X PUT "$api/admin/users/$uid" \
          --data "$(jq -n --arg l ${lib.escapeShellArg settings.user} '{storageLabel: $l}')"
        echo "set storage label"
      fi

      want=$(jq -n --arg p ${lib.escapeShellArg library} \
        '{importPaths: [$p], exclusionPatterns: ["**/${baseNameOf icfg.uploadDir}/**"]}')

      lib_id=$(curl -fsS "''${auth[@]}" "$api/libraries" \
        | jq -r --arg n ${lib.escapeShellArg icfg.libraryDir} '.[] | select(.name == $n) | .id')
      if [ -z "$lib_id" ]; then
        lib_id=$(curl -fsS "''${auth[@]}" -X POST "$api/libraries" \
          --data "$(jq --arg o "$uid" --arg n ${lib.escapeShellArg icfg.libraryDir} \
            '. + {ownerId: $o, name: $n}' <<<"$want")" \
          | jq -r .id)
        echo "created library ${icfg.libraryDir}"
      else
        # re-asserted, not created-with: an existing library would keep an
        # old path or exclusion otherwise
        curl -fsS -o /dev/null "''${auth[@]}" -X PUT "$api/libraries/$lib_id" --data "$want"
      fi

      # the boot scan, for whatever changed while the watch was down
      curl -fsS -o /dev/null "''${auth[@]}" -X POST "$api/libraries/$lib_id/scan"
      echo "scan queued"
    '';
  };
}
