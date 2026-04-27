{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/networking.nix
    ./modules/packages.nix
    ./modules/ssh.nix
    ./modules/bluetooth.nix
    ./modules/home-assistant.nix
    ./modules/jellyfin.nix
    ./modules/nextcloud.nix
    ./modules/pihole.nix
    ./modules/paperless.nix
    ./modules/users.nix
  ];

  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Keep multiple generations
  boot.loader.systemd-boot.configurationLimit = 10;

  # Enable boot counting / automatic retry logic
  boot.bootspec.enable = true;

  # Mark system healthy after successful boot
  systemd.services.boot-success = {
    description = "Mark current boot successful";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      /run/current-system/bin/bootctl set-successful || true
    '';
  };

  # reboot 30sec after kernel panic
  boot.kernelParams = [ "panic=30" ];

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
