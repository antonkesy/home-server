{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    cifs-utils
    git
    make
    neovim
    lazygit
    htop
    curl
    wget
  ];
}
