{ settings, ... }:

{
  programs.ssh = {
    startAgent = true;
    extraConfig = ''
      Host *
        AddKeysToAgent yes
    '';
  };

  services.openssh = {
    enable = true;
    ports = [ settings.ports.ssh ];
    settings = {
      PermitRootLogin = "no";
      # until a key is in modules/users.nix
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      MaxAuthTries = 3;
    };
  };
}
