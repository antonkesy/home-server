{ config, pkgs, ... }:

{
  # Create kavita directory
  systemd.tmpfiles.rules = [
    "d /var/lib/kavita 0755 kavita kavita -"
  ];

  # Kavita reading server
  systemd.services.kavita = {
    description = "Kavita Reading Server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    environment = {
      TZ = "Europe/Berlin";
      DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "true";
    };
    
    serviceConfig = {
      Type = "simple";
      User = "kavita";
      Group = "kavita";
      WorkingDirectory = "/var/lib/kavita";
      ExecStart = "${pkgs.kavita}/bin/kavita";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # Create kavita user
  users.users.kavita = {
    isSystemUser = true;
    group = "kavita";
    home = "/var/lib/kavita";
    createHome = true;
  };

  users.groups.kavita = {};
}
