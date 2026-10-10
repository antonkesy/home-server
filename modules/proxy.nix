{
  config,
  lib,
  settings,
  ...
}:

let
  inherit (settings) domain subdomains ports;
  fqdn = name: "${subdomains.${name}}.${domain}";

  # HOSTINGER_API_TOKEN=..., from `just acme-token`; hPanel > Account > API
  tokenFile = "/var/lib/acme/hostinger.env";

  # every subdomain but nextcloud, which is its own nginx vhost
  # (modules/nextcloud.nix) and only needs the certificate
  proxied = lib.removeAttrs subdomains [ "nextcloud" ];
  unknown = lib.subtractLists (lib.attrNames ports) (lib.attrNames proxied);

  vhost = name: {
    useACMEHost = domain;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString ports.${name}}";
      # home assistant, jellyfin, audiobookshelf, immich and paperless all
      # push over a websocket
      proxyWebsockets = true;
      extraConfig = ''
        # LAN only; immich takes whole videos in one request
        client_max_body_size 0;
        proxy_request_buffering off;
        # upstream immich and jellyfin; the recommended 60s cuts a long upload
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
      '';
    };
  };
in
{
  assertions = [
    {
      assertion = unknown == [ ];
      message = "settings.subdomains: no port for ${lib.concatStringsSep ", " unknown}";
    }
  ];

  # one wildcard instead of a certificate per name: nothing has to be reachable
  # from the internet, and the names stay out of the certificate logs
  security.acme = {
    acceptTerms = true;
    defaults.email = settings.adminEmail;
    certs.${domain} = {
      domain = "*.${domain}";
      dnsProvider = "hostinger";
      environmentFile = tokenFile;
      group = config.services.nginx.group;
    };
  };

  # until the token is there nginx serves the module's self-signed stand-in, and
  # the order is skipped rather than failing every switch
  systemd.services."acme-order-renew-${domain}".unitConfig.ConditionPathExists = tokenFile;

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts = lib.mapAttrs' (name: _: lib.nameValuePair (fqdn name) (vhost name)) proxied // {
      ${fqdn "pihole"}.locations."= /".return = "302 /admin/";

      # http://lab and anything else not named above: no vhost answers
      # by accident
      "_" = {
        default = true;
        rejectSSL = true;
        locations."/".return = "444";
      };
    };
  };

  # pi-hole serves /etc/hosts to the LAN (modules/networking.nix), so this is
  # all the DNS there is; the public zone never names lab
  networking.hosts.${settings.lan.address} = map fqdn (lib.attrNames subdomains);
}
