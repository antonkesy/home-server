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

    # Add your public key here, then set PasswordAuthentication = false in
    # modules/ssh.nix. Verify you can log in with the key before switching.
    openssh.authorizedKeys.keys = [ ];
  };
}
