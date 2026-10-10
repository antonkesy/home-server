{ settings, ... }:

{
  services.home-assistant = {
    enable = true;
    config = {
      default_config = { };
      http = {
        server_host = "0.0.0.0";
        server_port = settings.ports.homeAssistant;
        # nginx (modules/proxy.nix); a forwarded request from anywhere else
        # is refused
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };
    };
  };
}
