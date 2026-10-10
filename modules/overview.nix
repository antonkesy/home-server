{
  lib,
  pkgs,
  settings,
  ...
}:

let
  inherit (settings) domain subdomains ports;
  fqdn = name: "${subdomains.${name}}.${domain}";
  host = fqdn "overview";

  # what the page lists, in order; keys are those of settings.subdomains
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
          key = "pihole";
          name = "Pi-hole";
          about = "LAN DNS and ad blocking";
          color = "#b8323a";
        }
      ];
    }
  ];

  listed = lib.concatMap (g: map (s: s.key) g.services) groups;
  missing = lib.subtractLists (listed ++ [ "overview" ]) (lib.attrNames subdomains);

  # what /up/<key> asks; anything below 500 counts as up. nextcloud has no
  # port, so its own vhost is asked, over the name /etc/hosts gives it
  upstream =
    key:
    if key == "nextcloud" then
      "https://${fqdn key}/status.php"
    else
      "http://127.0.0.1:${toString ports.${key}}/";

  card = s: ''
    <a class="card" href="https://${fqdn s.key}" data-key="${s.key}">
      <span class="badge" style="--c: ${s.color}">${lib.substring 0 1 s.name}</span>
      <span class="text">
        <span class="name">${s.name}<span class="dot" title="checking"></span></span>
        <span class="about">${s.about}</span>
        <span class="host">${fqdn s.key}</span>
      </span>
    </a>
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
        display: flex; gap: 14px; align-items: flex-start; padding: 16px;
        background: var(--card); border: 1px solid var(--line); border-radius: 12px;
        color: inherit; text-decoration: none;
        transition: border-color .15s, transform .15s;
      }
      .card:hover, .card:focus-visible { border-color: var(--muted); transform: translateY(-1px); outline: none; }
      .badge {
        flex: none; display: grid; place-items: center; width: 42px; height: 42px;
        border-radius: 10px; background: var(--c); color: #fff; font-weight: 700; font-size: 19px;
      }
      .text { display: flex; flex-direction: column; min-width: 0; }
      .name { display: flex; align-items: center; gap: 8px; font-weight: 600; font-size: 16px; }
      .about { color: var(--muted); margin-top: 2px; }
      .host { color: var(--muted); font-size: 12px; margin-top: 6px; font-family: ui-monospace, monospace; }
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
        function mark(up) {
          dot.className = "dot " + (up ? "up" : "down");
          dot.title = up ? "up" : "down";
        }
        fetch("/up/" + card.dataset.key, { redirect: "manual", cache: "no-store" })
          .then(function (r) { mark(r.type === "opaqueredirect" || r.status < 500); })
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
