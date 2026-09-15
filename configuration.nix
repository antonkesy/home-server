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
    ./modules/users.nix
  ];

  # Drives log timestamps, Home Assistant automations, Paperless document dates
  # and the Pi-hole container clock. Change this if the server is not in Berlin.
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # Trim SSDs weekly; the root filesystem is on NVMe.
  services.fstrim.enable = true;

  # Small compressed swap so a memory spike (Nextcloud cron, Paperless OCR)
  # degrades instead of triggering the OOM killer. There is no swap partition.
  zramSwap.enable = true;

  # Do not change: this pins state-format compatibility to the release the
  # machine was first installed with.
  system.stateVersion = "24.11";

  programs.git.enable = true;
  programs.git.config = {
    user.name = "Anton Kesy";
    user.email = "anton@kesy.de";
    pull.rebase = true;
  };
}
