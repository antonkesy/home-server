{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/boot.nix
    ./modules/nix.nix
    ./modules/networking.nix
    ./modules/packages.nix
    ./modules/ssh.nix
    ./modules/bluetooth.nix
    ./modules/home-assistant.nix
    ./modules/jellyfin.nix
    ./modules/nextcloud.nix
    ./modules/pihole.nix
    ./modules/paperless.nix
    ./modules/secrets.nix
    ./modules/users.nix
  ];

  # also feeds Paperless dates and the Pi-hole container
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  services.fstrim.enable = true;

  # no swap partition
  zramSwap.enable = true;

  # don't change
  system.stateVersion = "24.11";

  programs.git.enable = true;
  programs.git.config = {
    user.name = "Anton Kesy";
    user.email = "anton@kesy.de";
    pull.rebase = true;
  };
}
