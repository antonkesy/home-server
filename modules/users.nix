{ config, pkgs, ... }:

{
  users.groups.lab = { };

  users.users.ak = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "lab"
      "networkmanager"
    ];
    packages = with pkgs; [ ];

    # add a key, verify login, then disable PasswordAuthentication in ssh.nix
    openssh.authorizedKeys.keys = [ ];
  };
}
