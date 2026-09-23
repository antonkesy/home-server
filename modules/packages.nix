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
    gptfdisk # sgdisk;
    wget
    dig # DNS routing
  ];
}
