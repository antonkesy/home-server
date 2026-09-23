{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
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
