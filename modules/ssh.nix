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
      PasswordAuthentication = true;
    };
    openFirewall = true;
  };
}
