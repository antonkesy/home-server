{ config, pkgs, ... }:

{
  users.groups.lab = {};

  users.users.ak = {
    isNormalUser = true;
    extraGroups = [ "lab" ];
    packages = with pkgs; [];
  };
}
