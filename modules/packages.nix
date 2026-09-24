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
    gptfdisk # sgdisk
    hdparm # disk power state
    wget
    dig # DNS routing
  ];
}
