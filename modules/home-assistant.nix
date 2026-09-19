{ settings, ... }:

{
  services.home-assistant = {
    enable = true;
    extraComponents = [ ];
    config = {
      default_config = { };
      http = {
        server_host = "0.0.0.0";
        server_port = settings.ports.homeAssistant;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };
    };
  };
}
