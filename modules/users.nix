{ settings, ... }:

{
  users.groups.${settings.group} = { };

  users.users.${settings.user} = {
    isNormalUser = true;
    # pi-hole's files are owned by this uid
    uid = 1000;
    extraGroups = [
      "wheel"
      settings.group
    ];
    # add a key, verify login, then PasswordAuthentication = false in ssh.nix
    openssh.authorizedKeys.keys = [ ];
  };
}
