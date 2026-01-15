{ config, pkgs, ... }:

{
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud30;
    hostName = "localhost";
    config = {
      adminpassFile = "/var/lib/nextcloud/admin-pass";
      dbtype = "sqlite";
    };
    settings = {
      overwriteprotocol = "http";
      default_phone_region = "US";
    };
    https = false;
  };
}
