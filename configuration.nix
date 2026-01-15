{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/hardware/r8125.nix
    ./modules/networking.nix
    ./modules/packages.nix
    ./modules/ssh.nix
    ./modules/bluetooth.nix
    ./modules/nas-mounts.nix
    ./modules/home-assistant.nix
    ./modules/jellyfin.nix
    ./modules/nextcloud.nix
    ./modules/blocky.nix
    ./modules/kavita.nix
    ./modules/users.nix
  ];

  # System configuration
  system.stateVersion = "24.11";

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
