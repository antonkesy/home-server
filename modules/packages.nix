{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    cifs-utils
    just
    jq
    rsync
    neovim
    lazygit
    htop
    duf # disk usage
    wget
    dig # DNS routing
  ];
}
