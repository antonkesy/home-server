{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    cifs-utils
    git
    gnumake
    neovim
    lazygit
    htop
    curl
    wget
  ];
}
