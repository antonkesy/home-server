{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    cifs-utils
    git
    just
    neovim
    lazygit
    htop
    curl
    wget
    dig # DNS routing
  ];
}
