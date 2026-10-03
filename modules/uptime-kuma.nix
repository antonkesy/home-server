{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  inherit (settings) ports lan;
  port = ports.uptimeKuma;
  url = "http://127.0.0.1:${toString port}";
  kuma = config.services.uptime-kuma.package;
  # not under /var/lib/uptime-kuma: that is a DynamicUser StateDirectory,
  # which systemd wants to own outright
  secretsDir = "/var/lib/autokuma";
  adminPass = "${secretsDir}/admin-pass";
  pushTokens = "${secretsDir}/push-tokens";
  runDir = "/run/uptime-kuma";

  # uptime kuma keeps its monitors in sqlite; autokuma reconciles them from
  # these files on every sync, the id being the file name. parent_name points
  # at a group's id. push monitors get their token substituted at runtime
  monitors = {
    services = {
      name = "Services";
      type = "group";
    };
    network = {
      name = "Network";
      type = "group";
    };
    host = {
      name = "Host";
      type = "group";
    };

    home-assistant = {
      name = "Home Assistant";
      type = "http";
      url = "http://localhost:${toString ports.homeAssistant}/";
      parent_name = "services";
    };
    jellyfin = {
      name = "Jellyfin";
      type = "http";
      url = "http://localhost:${toString ports.jellyfin}/health";
      parent_name = "services";
    };
    nextcloud = {
      name = "Nextcloud";
      type = "keyword";
      url = "http://localhost:${toString ports.nextcloud}/status.php";
      keyword = ''"installed":true'';
      parent_name = "services";
    };
    paperless = {
      name = "Paperless";
      type = "http";
      url = "http://localhost:${toString ports.paperless}/";
      parent_name = "services";
    };
    immich = {
      name = "Immich";
      type = "keyword";
      url = "http://localhost:${toString ports.immich}/api/server/ping";
      keyword = "pong";
      parent_name = "services";
    };
    pihole-web = {
      name = "Pi-hole";
      type = "http";
      url = "http://localhost:${toString ports.pihole}/admin/";
      parent_name = "services";
    };

    # what the clients use: the LAN address, not loopback
    pihole-dns = {
      name = "Pi-hole DNS";
      type = "dns";
      hostname = settings.hostName;
      dns_resolve_server = lan.address;
      port = ports.dns;
      dns_resolve_type = "A";
      parent_name = "network";
    };
    router = {
      name = "Router";
      type = "ping";
      hostname = lan.router;
      parent_name = "network";
    };
    internet = {
      name = "Internet";
      type = "http";
      url = "https://1.1.1.1/";
      interval = 300;
      parent_name = "network";
    };
    ssh = {
      name = "SSH";
      type = "port";
      hostname = "localhost";
      port = ports.ssh;
      parent_name = "network";
    };

    # fed by lab-health below; interval is how long a missing heartbeat is
    # tolerated
    storage-array = {
      name = "Storage array";
      type = "push";
      interval = 600;
      parent_name = "host";
    };
    root-disk = {
      name = "Root disk";
      type = "push";
      interval = 600;
      parent_name = "host";
    };
    # pushed by lab-backup (modules/backup.nix); sunday to the next monday
    backup = {
      name = "Backup";
      type = "push";
      interval = 8 * 24 * 3600;
      max_retries = 0;
      parent_name = "host";
    };
  };

  defaults = {
    interval = 60;
    max_retries = 2;
  };

  isPush = m: m.type == "push";

  toml = pkgs.formats.toml { };
  monitorFiles = pkgs.linkFarm "autokuma-monitors" (
    lib.mapAttrsToList (id: m: {
      name = "${id}.toml";
      path = toml.generate "${id}.toml" (
        defaults // m // lib.optionalAttrs (isPush m) { push_token = "@TOKEN_${id}@"; }
      );
    }) monitors
  );

  pushMonitors = lib.attrNames (lib.filterAttrs (_: isPush) monitors);

  # the first admin can only be created over the socket, and so can a
  # password change; both share this client
  adminJs = pkgs.writeText "uptime-kuma-admin.js" ''
    const { io } = require("socket.io-client");
    const [mode, url, user, newPass] = process.argv.slice(2);
    const pass = process.env.KUMA_PASSWORD;
    const fail = (m) => { console.error(m); process.exit(1); };
    const s = io(url, { transports: ["websocket"], reconnection: false });
    setTimeout(() => fail("timeout"), 30000);
    s.on("connect_error", (e) => fail("connect: " + e.message));
    s.on("connect", () => {
      if (mode === "setup") {
        s.emit("needSetup", (need) => {
          if (!need) { console.log("already set up"); process.exit(0); }
          s.emit("setup", user, pass, (r) => {
            if (!r.ok) fail("setup: " + r.msg);
            console.log("created admin " + user);
            process.exit(0);
          });
        });
      } else if (mode === "password") {
        s.emit("login", { username: user, password: pass, token: "" }, (r) => {
          if (!r.ok) fail("login: " + r.msg);
          s.emit("changePassword", { currentPassword: pass, newPassword: newPass }, (r) => {
            if (!r.ok) fail("changePassword: " + r.msg);
            console.log("password changed");
            process.exit(0);
          });
        });
      } else fail("usage: setup|password");
    });
  '';

  # `uptime-kuma-admin setup` / `uptime-kuma-admin password <new>`
  admin = pkgs.writeShellApplication {
    name = "uptime-kuma-admin";
    runtimeInputs = [
      pkgs.nodejs
      pkgs.coreutils
    ];
    runtimeEnv.NODE_PATH = "${kuma}/lib/node_modules/uptime-kuma/node_modules";
    text = ''
      mode=''${1:?setup|password}
      # by env, not argv: the password must not show in the process list
      KUMA_PASSWORD=$(cat ${adminPass}) node ${adminJs} "$mode" ${url} ${settings.user} "''${2:-}"
    '';
  };

  # `lab-health-push <monitor> up|down [msg]`; a failed push is reported, not
  # fatal, so lab-backup's ExecStartPost cannot fail a finished backup
  push = pkgs.writeShellApplication {
    name = "lab-health-push";
    runtimeInputs = [
      pkgs.curl
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = ''
      name=$1 status=$2 msg=''${3:-}
      token=$(grep "^$name=" ${pushTokens} | cut -d= -f2-)
      [ -n "$token" ] || { echo "no push token for $name" >&2; exit 0; }
      curl -fsS -o /dev/null --get "${url}/api/push/$token" \
        --data-urlencode "status=$status" --data-urlencode "msg=$msg" \
        || echo "push $name failed" >&2
    '';
  };
in
{
  assertions = [
    {
      assertion = lib.all (m: lib.elem m.parent_name (lib.attrNames monitors)) (
        lib.filter (m: m ? parent_name) (lib.attrValues monitors)
      );
      message = "uptime-kuma: a monitor's parent_name is not a monitor id";
    }
  ];

  services.uptime-kuma = {
    enable = true;
    # upstream assumes a reverse proxy and binds loopback
    settings = {
      HOST = "0.0.0.0";
      PORT = toString port;
    };
  };

  environment.systemPackages = [
    admin
    push
  ];

  # for modules/backup.nix
  system.build.lab-health-push = lib.getExe push;

  # the admin lives in the sqlite db, the monitors go through autokuma, whose
  # credentials and monitor files are rendered here. `just sync-monitors`
  # re-runs it
  systemd.services.uptime-kuma-setup = {
    description = "create the uptime kuma admin and render the autokuma monitors";
    wantedBy = [ "multi-user.target" ];
    requires = [ "uptime-kuma.service" ];
    after = [ "uptime-kuma.service" ];
    restartTriggers = [ monitorFiles ];
    path = with pkgs; [
      curl
      coreutils
      gnused
      gnugrep
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "uptime-kuma";
      RuntimeDirectoryPreserve = true;
      TimeoutStartSec = "3min";
    };
    script = ''
      set -euo pipefail

      # Type=simple: ready is when it answers
      for _ in $(seq 120); do
        curl -fsS -o /dev/null ${url}/ 2>/dev/null && break
        sleep 1
      done

      ${lib.getExe admin} setup

      # autokuma runs as a dynamic user: credentials by systemd, monitors by
      # file. the push tokens in them are reachable on the LAN anyway
      printf 'AUTOKUMA__KUMA__USERNAME=%s\nAUTOKUMA__KUMA__PASSWORD=%s\n' \
        ${settings.user} "$(cat ${adminPass})" | install -m 0600 /dev/stdin ${runDir}/autokuma.env

      rm -rf ${runDir}/monitors
      install -d -m 0755 ${runDir}/monitors
      install -m 0644 ${monitorFiles}/*.toml ${runDir}/monitors/
      ${lib.concatMapStringsSep "\n" (id: ''
        token=$(grep '^${id}=' ${pushTokens} | cut -d= -f2-)
        sed -i "s|@TOKEN_${id}@|$token|" ${runDir}/monitors/${id}.toml
      '') pushMonitors}
    '';
  };

  # syncs the monitor files into uptime kuma; one it created and no longer
  # finds a file for is deleted after the grace period
  systemd.services.autokuma = {
    description = "sync the monitors into uptime kuma";
    wantedBy = [ "multi-user.target" ];
    requires = [ "uptime-kuma-setup.service" ];
    after = [ "uptime-kuma-setup.service" ];
    environment = {
      AUTOKUMA__KUMA__URL = url;
      AUTOKUMA__DOCKER__ENABLED = "false";
      AUTOKUMA__STATIC_MONITORS = "${runDir}/monitors";
      AUTOKUMA__SYNC_INTERVAL = "60";
      AUTOKUMA__DELETE_GRACE_PERIOD = "300";
    };
    serviceConfig = {
      ExecStart = lib.getExe pkgs.autokuma;
      EnvironmentFile = "${runDir}/autokuma.env";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # the host checks behind the push monitors. nothing here reads the array:
  # mdstat, the mount table and `df /` leave the disks asleep
  systemd.services.lab-health = {
    description = "push the host checks to uptime kuma";
    path = with pkgs; [
      coreutils
      gnugrep
      util-linux
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      push=${lib.getExe push}

      if grep -q '\[U*_U*\]' /proc/mdstat; then
        "$push" storage-array down "mirror degraded"
      elif ! mountpoint -q ${settings.storage.root}; then
        "$push" storage-array down "not mounted"
      else
        "$push" storage-array up "clean"
      fi

      free=$(df --output=avail --block-size=1G / | tail -n1 | tr -dc '0-9')
      if [ "$free" -lt ${toString settings.nextcloud.previewMinFreeGB} ]; then
        "$push" root-disk down "''${free}G free"
      else
        "$push" root-disk up "''${free}G free"
      fi
    '';
  };

  systemd.timers.lab-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = settings.uptimeKuma.healthOnCalendar;
      Unit = "lab-health.service";
    };
  };
}
