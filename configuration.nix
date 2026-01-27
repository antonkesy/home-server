{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/networking.nix
    ./modules/packages.nix
    ./modules/ssh.nix
    ./modules/bluetooth.nix
    ./modules/nas-mounts.nix
    ./modules/home-assistant.nix
    ./modules/jellyfin.nix
    ./modules/nextcloud.nix
    ./modules/pihole.nix
    ./modules/kavita.nix
    ./modules/users.nix
  ];

  # Boot loader
  boot.loader.systemd-boot.enable = true;

  # System configuration
  system.stateVersion = "24.11";

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Git configuration
  programs.git.enable = true;
  programs.git.config = {
    user.name = "Anton Kesy";
    user.email = "anton@kesy.de";
    pull.rebase = true;
  };
}
