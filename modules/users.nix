{ pkgs, settings, ... }:

{
  users.groups.${settings.group} = { };

  users.users.${settings.user} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      settings.group
      "networkmanager"
    ];
    packages = with pkgs; [ ];

    # add a key, verify login, then disable PasswordAuthentication in ssh.nix
    openssh.authorizedKeys.keys = [ ];
  };
}
