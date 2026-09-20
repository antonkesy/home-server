{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    cifs-utils
    git
    just
    neovim
    lazygit
    htop
    duf # disk usage
    curl
    wget
    dig # DNS routing
  ];
}
