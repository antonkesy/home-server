{ settings, ... }:

{
  services.home-assistant = {
    enable = true;
    config = {
      default_config = { };
      http = {
        server_host = "0.0.0.0";
        server_port = settings.ports.homeAssistant;
      };
    };
  };
}
