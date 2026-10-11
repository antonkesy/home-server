{
  config,
  pkgs,
  settings,
  ...
}:

let
  cfg = config.services.home-assistant;

  # since 2026.9 home assistant imports `http:` from configuration.yaml once,
  # stages it as a trial that reverts unless confirmed in the ui within 5 min,
  # and ignores the yaml after. so the store itself is written on every start,
  # as the already confirmed config; a change made in the ui (settings >
  # system > network) lasts until the next restart
  httpStore = pkgs.writeText "hass-http.json" (
    builtins.toJSON {
      version = 2;
      minor_version = 2;
      key = "http";
      data = {
        stable = {
          server_host = [ "0.0.0.0" ];
          server_port = settings.ports.homeAssistant;
          # nginx (modules/proxy.nix); a forwarded request from anywhere else
          # is refused
          use_x_forwarded_for = true;
          trusted_proxies = [
            "127.0.0.1/32"
            "::1/128"
          ];
          # the rest are home assistant's defaults
          cors_allowed_origins = [ "https://cast.home-assistant.io" ];
          login_attempts_threshold = -1;
          ip_ban_enabled = true;
          ssl_profile = "modern";
          use_x_frame_options = true;
          created_at = "1970-01-01T00:00:00+00:00";
          error = null;
          error_message = null;
        };
        pending = null;
        yaml_migration_done = true;
      };
    }
  );
in
{
  services.home-assistant = {
    enable = true;
    config = {
      default_config = { };
    };
  };

  systemd.services.home-assistant = {
    preStart = ''
      install -D -m 600 ${httpStore} "${cfg.configDir}/.storage/http"
    '';
    # the store is only read at start; a reload would keep the old one
    restartTriggers = [ httpStore ];
  };
}
