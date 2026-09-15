{ config, pkgs, ... }:

{
  # Run a user ssh-agent managed by NixOS, so SSH_AUTH_SOCK is set automatically.
  programs.ssh = {
    startAgent = true;
    extraConfig = ''
      Host *
        AddKeysToAgent yes
    '';
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      # no keys deployed yet; set false once authorizedKeys works
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      MaxAuthTries = 3;
    };
    openFirewall = true;
  };
}
