{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    just
    jq
    yq-go # YouTube/subscriptions.yaml
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
