{ config, pkgs, ... }:

let
  port = 8080;
  host = config.networking.hostName;
in
{
  services.nextcloud = {
    enable = true;
    # one major version per upgrade; 33 only after 32 has migrated
    package = pkgs.nextcloud32;
    hostName = host;
    config = {
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
}
