{ config, pkgs, ... }:

{
  users.groups.lab = {};

  users.users.ak = {
    isNormalUser = true;
    extraGroups = [ "wheel" "lab" "networkmanager" ];
    packages = with pkgs; [];
  };
}
