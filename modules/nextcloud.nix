{ config, pkgs, ... }:

let
  port = 8080;
  host = config.networking.hostName;
in
{
  services.nextcloud = {
    enable = true;
    # Nextcloud only supports one major version per upgrade. Bump to
    # nextcloud33 only after 32 has finished migrating (`nextcloud-occ status`).
    package = pkgs.nextcloud32;
    hostName = host;
    config = {
      adminpassFile = "/var/lib/nextcloud/admin-pass";
      dbtype = "sqlite";
    };
    settings = {
      overwriteprotocol = "http";
      # Without the port, Nextcloud hands out redirects and share links that
      # point back at :80, where nothing is listening.
      overwritehost = "${host}:${toString port}";
      default_phone_region = "DE";
      trusted_domains = [ "localhost" ];
    };
    https = false;
    maxUploadSize = "4G";
  };

  # services.nextcloud parks its nginx vhost on port 80. Every other service
  # here is addressed by port, so pin it to 8080 to match the documented URL.
  services.nginx.virtualHosts.${host}.listen = [
    {
      addr = "0.0.0.0";
      inherit port;
    }
  ];
}
