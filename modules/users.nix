{ config, pkgs, ... }:

{
  users.users.homeserver = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    packages = with pkgs; [];
  };
}
