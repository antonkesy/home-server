{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  inherit (settings) domain subdomains ports;
  fqdn = name: "${subdomains.${name}}.${domain}";
  host = fqdn "overview";

  # what the page lists, in order; keys are those of settings.subdomains.
  # one without a subdomain says where its card leads instead: href, and
  # where, the text in place of the subdomain
  groups = [
    {
      title = "Media";
      services = [
        {
          key = "jellyfin";
          name = "Jellyfin";
          about = "Movies, shows, music, YouTube";
          color = "#7b5cd6";
        }
        {
          key = "immich";
          name = "Immich";
          about = "Photos and the phone's camera roll";
          color = "#3d7de0";
        }
        {
          key = "audiobookshelf";
          name = "Audiobookshelf";
          about = "Audiobooks and podcasts";
          color = "#c7802c";
        }
        {
          key = "bookOrbit";
          name = "BookOrbit";
          about = "Ebooks, Kobo sync";
          color = "#2f9e8f";
        }
        {
          key = "musicGrabber";
          name = "MusicGrabber";
          about = "Search a song, download it into Music";
          color = "#d0457a";
        }
      ];
    }
    {
      title = "Files";
      services = [
        {
          key = "nextcloud";
          name = "Nextcloud";
          about = "Every share on the array";
          color = "#1f7fc4";
        }
        {
          key = "paperless";
          name = "Paperless-ngx";
          about = "Scanned documents, searchable";
          color = "#3f8f4f";
        }
      ];
    }
    {
      title = "Home & network";
      services = [
        {
          key = "homeAssistant";
          name = "Home Assistant";
          about = "Devices and automations";
          color = "#1c9ad6";
        }
        {
          key = "matter";
          name = "Matter";
          about = "Matter devices, paired from Home Assistant";
          color = "#4b5bb5";
          # no ui of its own (modules/matter.nix)
          href = "https://${fqdn "homeAssistant"}/config/integrations/integration/matter";
          where = "via ${fqdn "homeAssistant"}";
        }
        {
          key = "zigbee";
          name = "Zigbee";
          about = "Zigbee devices, through the Sonoff dongle";
          color = "#c9952b";
          # zha, inside home assistant (modules/home-assistant.nix)
          href = "https://${fqdn "homeAssistant"}/config/integrations/integration/zha";
          where = "via ${fqdn "homeAssistant"}";
        }
        {
          key = "bluetooth";
          name = "Bluetooth";
          about = "BLE devices for Home Assistant";
          color = "#2a6dd4";
          href = "https://${fqdn "homeAssistant"}/config/integrations/integration/bluetooth";
          where = "via ${fqdn "homeAssistant"}";
        }
        {
          key = "pihole";
          name = "Pi-hole";
          about = "LAN DNS and ad blocking";
          color = "#b8323a";
        }
        {
          key = "tailscale";
          name = "Tailscale";
          about = "lab and the LAN from anywhere";
          color = "#4a4f57";
          href = "https://login.tailscale.com/admin/machines";
          where = "login.tailscale.com";
        }
      ];
    }
    {
      title = "Chat";
      services = [
        {
          key = "gamja";
          name = "gamja";
          about = "IRC in the browser, through soju";
          color = "#5a6fb0";
        }
        {
          key = "soju";
          name = "soju";
          about = "IRC bouncer, stays on Libera";
          color = "#8a5a44";
          # irc, not a page (modules/soju.nix); the link opens an irc client
          href = "ircs://${sojuHost}:${toString ports.soju}";
          where = "${sojuHost}:${toString ports.soju}";
        }
      ];
    }
    {
      title = "System";
      services = [
        {
          key = "storage";
          name = "Storage";
          about = "The RAID1 mirror under every share";
          color = "#6a7280";
          # nothing to open; the mirror is `just storage`
          href = null;
          where = settings.storage.root;
        }
        {
          key = "backup";
          name = "Backup";
          about = "Config and secrets, every ${settings.backup.onCalendar}";
          color = "#3f7f86";
          href = "https://${fqdn "nextcloud"}/apps/files/?dir=/${backupShare}";
          where = backupShare;
        }
        {
          key = "certificate";
          name = "Certificate";
          about = "The *.${domain} wildcard, from Let's Encrypt";
          color = "#5b8c3a";
          href = null;
          where = "acme-renew-${domain}.timer";
        }
      ];
    }
  ];

  # Backups/lab: the backup dir as nextcloud names it, an external storage per
  # top-level directory of the array
  backupShare = lib.removePrefix "${settings.storage.root}/" settings.backup.dir;

  # what /up/<key> runs for a card with no http of its own: exit 0 is up, and
  # what it prints is shown on the card. none of them touches the array's
  # disks, which would wake them on every visit
  certDir = config.security.acme.certs.${domain}.directory;
  checks = {
    # zha keeps the radio's serial port open for as long as it runs
    zigbee = ''
      pid=$(systemctl show -p MainPID --value home-assistant.service)
      if [ "$pid" = 0 ]; then
        echo "home assistant is not running"
        return 1
      fi
      for fd in /proc/"$pid"/fd/*; do
        t=$(readlink "$fd" || true)
        case $t in
          /dev/ttyUSB* | /dev/ttyACM*)
            echo "radio open at $t"
            return 0
            ;;
        esac
      done
      echo "no radio open; the dongle is unplugged or zha is not set up"
      return 1
    '';
    bluetooth = ''
      out=$(timeout 5 bluetoothctl show 2>&1 || true)
      case $out in
        *"Powered: yes"*) echo "adapter powered" ;;
        *"Powered: no"*)
          echo "adapter off"
          return 1
          ;;
        *)
          echo "no adapter"
          return 1
          ;;
      esac
    '';
    tailscale = ''
      state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty' || true)
      case $state in
        Running) echo "connected" ;;
        NeedsLogin)
          echo "logged out; \`just tailscale-up\`"
          return 1
          ;;
        *)
          echo "''${state:-not running}"
          return 1
          ;;
      esac
    '';
    # sysfs and the mount table only
    storage = ''
      src=$(findmnt -n -o SOURCE --mountpoint ${settings.storage.root} || true)
      if [ -z "$src" ]; then
        echo "not mounted"
        return 1
      fi
      md=/sys/block/''${src##*/}/md
      degraded=$(cat "$md/degraded")
      if [ "$degraded" != 0 ]; then
        echo "degraded, $degraded disk(s) missing"
        return 1
      fi
      echo "$(cat "$md/array_state"), $(cat "$md/raid_disks") disks"
    '';
    # touched by lab-backup on success (modules/backup.nix); weekly, so a
    # day of slack
    backup = ''
      stamp=/var/lib/lab-backup/last-success
      if [ ! -e "$stamp" ]; then
        echo "no backup yet"
        return 1
      fi
      last=$(date -r "$stamp" '+%a %-d %b')
      if [ $(($(date +%s) - $(stat -c %Y "$stamp"))) -gt $((8 * 86400)) ]; then
        echo "last one $last, overdue"
        return 1
      fi
      echo "last one $last"
    '';
    # renewal starts 30 days out, so two weeks left means it is failing
    certificate = ''
      cert=${certDir}/fullchain.pem
      if ! issuer=$(openssl x509 -noout -issuer -in "$cert" 2>/dev/null); then
        echo "no certificate"
        return 1
      fi
      until=$(date -d "$(openssl x509 -noout -enddate -in "$cert" | cut -d= -f2)" '+%-d %b %Y')
      case $issuer in
        *minica*)
          echo "self-signed stand-in; \`just acme-token\`"
          return 1
          ;;
      esac
      if ! openssl x509 -noout -checkend $((14 * 86400)) -in "$cert" >/dev/null; then
        echo "expires $until, renewal failing"
        return 1
      fi
      echo "valid until $until"
    '';
  };

  # one connection per request (Accept=yes), the path is the check
  statusSocket = "/run/lab-status.sock";
  status = pkgs.writeShellApplication {
    name = "lab-status";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.jq
      pkgs.openssl
      pkgs.bluez
      config.systemd.package
      config.services.tailscale.package
    ];
    text = ''
      read -r _ path _ || exit 0
      # the headers too, or closing on them unread resets the connection
      while IFS= read -r line && [ -n "''${line%$'\r'}" ]; do :; done

      ${lib.concatStrings (
        lib.mapAttrsToList (key: body: ''
          check_${key}() {
            ${body}
          }
        '') checks
      )}

      key=''${path#/}
      if ! declare -F "check_$key" >/dev/null; then
        code="404 Not Found"
        out="no such check"
      elif out=$("check_$key" 2>&1); then
        code="200 OK"
      else
        code="503 Service Unavailable"
      fi
      printf 'HTTP/1.0 %s\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n\r\n%s\n' "$code" "$out"
    '';
  };

  sojuHost = config.services.soju.hostName;
  # the ircs port speaks no http, so the dot asks soju's local http socket
  sojuSocket = lib.removePrefix "http+unix://" (
    lib.findFirst (lib.hasPrefix "http+unix://") (throw "soju has no http+unix listener")
      config.services.soju.listen
  );

  listed = lib.concatMap (g: map (s: s.key) g.services) groups;
  missing = lib.subtractLists (listed ++ [ "overview" ]) (lib.attrNames subdomains);

  # what /up/<key> asks; anything below 500 counts as up. nextcloud's port
  # is only nginx's copy of its vhost, so the vhost itself is asked, over the
  # name /etc/hosts gives it. matter's port is local only, so not in ports.
  # soju answers anything with a 404, which is up; gamja is static files
  # beside soju's websocket, so soju is what can be down
  upstream =
    key:
    if key == "nextcloud" then
      "https://${fqdn key}/status.php"
    else if key == "matter" then
      "http://127.0.0.1:${toString config.services.matter-server.port}/"
    else if key == "soju" || key == "gamja" then
      "http://unix:${sojuSocket}:/"
    else if checks ? ${key} then
      "http://unix:${statusSocket}:/${key}"
    else
      "http://127.0.0.1:${toString ports.${key}}/";

  # the port each service still answers on directly, as http://lab:<port>;
  # pi-hole's UI is under /admin; soju's port is ircs, already the card's link
  direct =
    key:
    lib.optionalString (ports ? ${key} && key != "soju") (
      "${settings.hostName}:${toString ports.${key}}" + lib.optionalString (key == "pihole") "/admin"
    );

  # the whole card opens the subdomain; the port is its own link on top. a
  # card whose href is null opens nothing. a check's answer is its own line
  card =
    s:
    let
      link = s.href or "https://${fqdn s.key}";
      title = ''${s.name}<span class="dot" title="checking"></span>'';
    in
    ''
      <div class="card" data-key="${s.key}">
        <span class="badge" style="--c: ${s.color}">${lib.substring 0 1 s.name}</span>
        <span class="text">
          ${
            if link == null then
              ''<span class="name">${title}</span>''
            else
              ''<a class="name" href="${link}">${title}</a>''
          }
          <span class="about">${s.about}</span>
          ${lib.optionalString (checks ? ${s.key}) ''<span class="detail"></span>''}
        <span class="links">
          <span>${s.where or (fqdn s.key)}</span>
          ${lib.optionalString (
            direct s.key != ""
          ) ''<a href="http://${direct s.key}">${direct s.key}</a>''}
          </span>
        </span>
      </div>
    '';

  group = g: ''
    <section>
      <h2>${g.title}</h2>
      <div class="grid">
        ${lib.concatMapStrings card g.services}
      </div>
    </section>
  '';

  page = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${settings.hostName}</title>
    <style>
      :root {
        --bg: #f4f5f7; --card: #fff; --fg: #1d2129; --muted: #626a77;
        --line: #e2e5ea; --up: #2f9e5b; --down: #c9433b;
        color-scheme: light dark;
      }
      @media (prefers-color-scheme: dark) {
        :root {
          --bg: #15171b; --card: #1e2126; --fg: #e8eaee; --muted: #9aa1ad;
          --line: #2c3037; --up: #4cc27c; --down: #e5615a;
        }
      }
      * { box-sizing: border-box; }
      body {
        margin: 0; background: var(--bg); color: var(--fg);
        font: 15px/1.4 system-ui, -apple-system, "Segoe UI", sans-serif;
      }
      main { max-width: 980px; margin: 0 auto; padding: 40px 16px 56px; }
      header { display: flex; align-items: baseline; gap: 12px; margin-bottom: 28px; }
      h1 { margin: 0; font-size: 28px; letter-spacing: -0.01em; }
      header span { color: var(--muted); }
      h2 {
        margin: 28px 0 12px; font-size: 13px; font-weight: 600;
        text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted);
      }
      .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 12px; }
      .card {
        position: relative; display: flex; gap: 14px; align-items: flex-start; padding: 16px;
        background: var(--card); border: 1px solid var(--line); border-radius: 12px;
        transition: border-color .15s, transform .15s;
      }
      .card:hover, .card:focus-within { border-color: var(--muted); transform: translateY(-1px); }
      .card a { color: inherit; text-decoration: none; }
      a.name::after { content: ""; position: absolute; inset: 0; border-radius: inherit; }
      .name:focus-visible { outline: none; }
      .badge {
        flex: none; display: grid; place-items: center; width: 42px; height: 42px;
        border-radius: 10px; background: var(--c); color: #fff; font-weight: 700; font-size: 19px;
      }
      .text { display: flex; flex-direction: column; min-width: 0; }
      .name { display: flex; align-items: center; gap: 8px; font-weight: 600; font-size: 16px; }
      .about { color: var(--muted); margin-top: 2px; }
      .detail { margin-top: 2px; font-size: 13px; }
      .detail.down { color: var(--down); }
      .links {
        display: flex; flex-direction: column; align-items: flex-start; gap: 2px; margin-top: 6px;
        color: var(--muted); font-size: 12px; font-family: ui-monospace, monospace;
      }
      .links a { position: relative; z-index: 1; text-decoration: underline dotted; }
      .links a:hover { color: var(--fg); }
      .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--line); }
      .dot.up { background: var(--up); }
      .dot.down { background: var(--down); }
    </style>
    </head>
    <body>
    <main>
      <header><h1>${settings.hostName}</h1><span>${settings.lan.address}</span></header>
      ${lib.concatMapStrings group groups}
    </main>
    <script>
      // /up/<key> is proxied to the service on this same vhost; a 502 is down
      document.querySelectorAll(".card").forEach(function (card) {
        var dot = card.querySelector(".dot");
        var detail = card.querySelector(".detail");
        function mark(up, text) {
          dot.className = "dot " + (up ? "up" : "down");
          dot.title = up ? "up" : "down";
          if (detail) {
            detail.className = "detail" + (up ? "" : " down");
            detail.textContent = text || (up ? "" : "no answer");
          }
        }
        fetch("/up/" + card.dataset.key, { redirect: "manual", cache: "no-store" })
          .then(function (r) {
            var up = r.type === "opaqueredirect" || r.status < 500;
            // a check answers in plain text; nginx's own 502 page is html
            var own = (r.headers.get("content-type") || "").indexOf("text/plain") === 0;
            if (detail && own) return r.text().then(function (t) { mark(up, t.trim()); });
            mark(up);
          })
          .catch(function () { mark(false); });
      });
    </script>
    </body>
    </html>
  '';
in
{
  assertions = [
    {
      assertion = missing == [ ];
      message = "modules/overview.nix lists no card for ${lib.concatStringsSep ", " missing}";
    }
  ];

  # root, for /proc and the tailscale and bluez sockets; nginx alone may ask
  systemd.sockets.lab-status = {
    description = "the start page's checks";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = statusSocket;
      Accept = true;
      SocketGroup = config.services.nginx.group;
      SocketMode = "0660";
    };
  };
  systemd.services."lab-status@" = {
    description = "one start page check";
    serviceConfig = {
      ExecStart = lib.getExe status;
      StandardInput = "socket";
      StandardOutput = "socket";
      StandardError = "journal";
      RuntimeMaxSec = "30s";
    };
  };

  # the certificate is modules/proxy.nix's wildcard
  services.nginx.virtualHosts.${host} = {
    useACMEHost = domain;
    forceSSL = true;
    root = page;
    locations = lib.listToAttrs (
      map (
        key:
        lib.nameValuePair "= /up/${key}" {
          proxyPass = upstream key;
          # the recommended Host is this vhost's, which would ask the overview
          # itself instead of nextcloud
          recommendedProxySettings = key != "nextcloud";
          extraConfig = ''
            proxy_connect_timeout 3s;
            proxy_read_timeout 10s;
          ''
          + lib.optionalString (key == "nextcloud") ''
            proxy_set_header Host ${fqdn key};
            proxy_ssl_server_name on;
            proxy_ssl_name ${fqdn key};
          '';
        }
      ) listed
    );
  };
}
