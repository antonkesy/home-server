{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  bcfg = settings.bookOrbit;
  port = settings.ports.bookOrbit;
  host = config.networking.hostName;
  stateDir = "/var/lib/bookorbit";
  # covers, the upload staging area (book-bucket), the book dock
  dataDir = "${stateDir}/data";
  # JWT_SECRET, SETUP_BOOTSTRAP_TOKEN, PODCAST_ENCRYPTION_KEY, from gen-secrets
  secretsEnv = "${stateDir}/bookorbit.env";
  adminPass = "${stateDir}/admin-pass";
  uid = toString config.users.users.${settings.user}.uid;
  # the oci-containers module's RuntimeDirectory is the container name
  envFile = "/run/bookorbit/env";

  db = "bookorbit";
  pgSocket = "/run/postgresql";

  # the first account. upstream wants three characters of username, which
  # `ak` is not, so the email is the login, as with immich. the Kobo and
  # email links are built from APP_URL
  adminEmail = settings.adminEmail;
  appUrl = "http://${host}.${settings.lan.domain}:${toString port}";
  api = "http://localhost:${toString port}/api/v1";

  # ak's uid is fixed (modules/users.nix), lab's gid is allocated by nixos
  pgid = pkgs.writeShellScript "bookorbit-pgid" ''
    printf 'PGID=%s\n' "$(${lib.getExe pkgs.getent} group ${settings.group} | cut -d: -f3)" \
      > ${envFile}
  '';

  # what the app's migrate step would create itself; done here as superuser
  # so the role never needs more than ownership of its database
  extensions = [
    "uuid-ossp"
    "pg_trgm"
    "unaccent"
    "vector"
  ];
  extensionsSql = pkgs.writeText "bookorbit-extensions.sql" (
    lib.concatMapStringsSep "\n" (ext: ''CREATE EXTENSION IF NOT EXISTS "${ext}";'') extensions
  );
in
{
  assertions = [
    {
      assertion =
        lib.elem (baseNameOf bcfg.dir) settings.storage.dirs && dirOf bcfg.dir == settings.storage.root;
      message = "settings.bookOrbit.dir must be one of storage.dirs";
    }
  ];

  # the container runs as ak (PUID) and chowns /data to him on start; the
  # secrets next to it stay root's, podman reads them
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 root root -"
    "d ${dataDir} 0750 ${uid} ${uid} -"
  ];

  # peer auth over the unix socket, like nextcloud and immich: the container
  # has no user namespace, so the server sees uid ${uid}, i.e. ak, and the map
  # turns that into the bookorbit role. no password anywhere
  services.postgresql = {
    ensureDatabases = [ db ];
    ensureUsers = [
      {
        name = db;
        ensureDBOwnership = true;
      }
    ];
    extensions = ps: [ ps.pgvector ];
    # before the module's `local all all peer`, which has no map
    authentication = ''
      local ${db} ${db} peer map=${db}
    '';
    identMap = ''
      ${db} ${settings.user} ${db}
    '';
  };

  # immich's module does the same for its extensions; a restore re-runs it
  systemd.services.postgresql-setup.serviceConfig.ExecStartPost = [
    ''
      ${lib.getExe' config.services.postgresql.package "psql"} -d ${db} -f ${extensionsSql}
    ''
  ];

  virtualisation.oci-containers.containers.bookorbit = {
    image = bcfg.image;

    environment = {
      TZ = config.time.timeZone;
      NODE_ENV = "production";
      PORT = "3000";
      APP_URL = appUrl;
      # the host's postgres over its socket, bind-mounted below
      DATABASE_URL = "postgres://${db}@localhost/${db}?host=${pgSocket}";
      # the folder picker starts in the library, not in the container root
      LIBRARY_BROWSE_ROOT = "/books";
      # files it writes into /books are chowned to this; the group comes from
      # the env file
      PUID = uid;
    };
    environmentFiles = [
      envFile
      secretsEnv
    ];

    volumes = [
      "${bcfg.dir}:/books"
      "${dataDir}:/data"
      "${pgSocket}:${pgSocket}"
    ];

    ports = [ "${toString port}:3000/tcp" ];

    # upstream compose: read-only root, /tmp in memory, the capabilities the
    # entrypoint needs to chown /data and drop to PUID. tini is its entrypoint
    extraOptions = [
      "--read-only"
      "--tmpfs=/tmp"
      "--cap-drop=ALL"
      "--cap-add=CHOWN"
      "--cap-add=DAC_OVERRIDE"
      "--cap-add=FOWNER"
      "--cap-add=SETGID"
      "--cap-add=SETUID"
      "--security-opt=no-new-privileges"
      "--stop-timeout=30"
    ];
  };

  systemd.services.podman-bookorbit = {
    # the database and its role exist once the target is reached
    requires = [ "postgresql.target" ];
    after = [ "postgresql.target" ];
    # a bind of an unmounted array would build Books/ on the SSD
    unitConfig.RequiresMountsFor = [ bcfg.dir ];
    path = [ pkgs.coreutils ];
    serviceConfig.ExecStartPre = lib.mkBefore [ "${pgid}" ];
  };

  # the first account, over the token-gated setup endpoint; the counterpart
  # of immich-setup. a later password change in the UI is not put back
  systemd.services.bookorbit-setup = {
    description = "create the bookorbit admin";
    wantedBy = [ "multi-user.target" ];
    requires = [ "podman-bookorbit.service" ];
    after = [ "podman-bookorbit.service" ];
    path = with pkgs; [
      coreutils
      curl
      gnugrep
      jq
    ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "5min";
    };
    script = ''
      set -euo pipefail

      api=${api}
      # the migrations run before it listens
      for _ in $(seq 240); do
        curl -fsS -o /dev/null "$api/health" 2>/dev/null && break
        sleep 1
      done
      curl -fsS -o /dev/null "$api/health"

      if [ "$(curl -fsS "$api/auth/setup-status" | jq -r .needsSetup)" != true ]; then
        echo "already set up"
        exit 0
      fi

      token=$(grep '^SETUP_BOOTSTRAP_TOKEN=' ${secretsEnv} | cut -d= -f2-)
      # the body says which field it did not like
      reply=$(curl -sS -w '\n%{http_code}' -X POST "$api/auth/setup" \
        -H "x-setup-token: $token" -H 'Content-Type: application/json' \
        --data "$(jq -n --arg u ${lib.escapeShellArg adminEmail} --arg n ${lib.escapeShellArg settings.user} \
          --arg p "$(cat ${adminPass})" '{username: $u, name: $n, email: $u, password: $p}')")
      code=''${reply##*$'\n'}
      [ "$code" = 201 ] || { echo "setup returned $code: ''${reply%$'\n'*}" >&2; exit 1; }
      echo "created admin ${adminEmail}"
    '';
  };
}
