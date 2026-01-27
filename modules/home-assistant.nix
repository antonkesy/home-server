{ config, pkgs, ... }:

{
  services.home-assistant = {
    enable = true;
    port = 8123;
    openFirewall = true;
    extraComponents = [
      "esphome"
      "met"
      "radio_browser"
    ];
    config = {
      default_config = {};
      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
        trusted_proxies = [ "127.0.0.1" "::1" ];
      };
    };
  };
}
