{ settings, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/boot.nix
    ./modules/nix.nix
    ./modules/networking.nix
    ./modules/packages.nix
    ./modules/ssh.nix
    ./modules/backup.nix
    ./modules/bluetooth.nix
    ./modules/home-assistant.nix
    ./modules/jellyfin.nix
    ./modules/nas.nix
    ./modules/nextcloud.nix
    ./modules/on-demand.nix
    ./modules/pihole.nix
    ./modules/paperless.nix
    ./modules/secrets.nix
    ./modules/users.nix
  ];

  # also feeds Paperless dates and the Pi-hole container
  time.timeZone = settings.timeZone;
  i18n.defaultLocale = settings.locale;

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
