{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    cifs-utils
    git
    vim
    htop
    curl
    wget
  ];
}
