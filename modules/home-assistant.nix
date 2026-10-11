{ ... }:

{
  services.home-assistant = {
    enable = true;
    config = {
      default_config = { };
      # no `http:` here: since 2026.9 home assistant imports it once into
      # .storage/http and ignores the yaml after. bind address, port and the
      # reverse proxy (use_x_forwarded_for, trusted 127.0.0.1 and ::1 for
      # nginx, modules/proxy.nix) are set in the ui, settings > system >
      # network; a change there must be confirmed within 5 min of the restart
      # or it reverts. the port is settings.ports.homeAssistant's default 8123
    };
  };
}
