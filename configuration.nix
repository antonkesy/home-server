{ settings, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/boot.nix
    ./modules/storage.nix
    ./modules/nix.nix
    ./modules/networking.nix
    ./modules/packages.nix
    ./modules/ssh.nix
    ./modules/tailscale.nix
    ./modules/audiobookshelf.nix
    ./modules/backup.nix
    ./modules/bookorbit.nix
    ./modules/bluetooth.nix
    ./modules/home-assistant.nix
    ./modules/immich.nix
    ./modules/jellyfin.nix
    ./modules/musicgrabber.nix
    ./modules/nextcloud.nix
    ./modules/overview.nix
    ./modules/pihole.nix
    ./modules/proxy.nix
    ./modules/paperless.nix
    ./modules/secrets.nix
    ./modules/users.nix
    ./modules/ytdl-sub.nix
  ];

  time.timeZone = settings.timeZone;
  i18n.defaultLocale = settings.locale;

  # sunday, after the nix jobs (modules/nix.nix)
  services.fstrim.interval = "Sun 04:30";

  # no swap partition
  zramSwap.enable = true;

  # deliberately not powerManagement.powertop.enable: --auto-tune turns on usb
  # autosuspend, which makes an external disk enclosure throw i/o errors
  powerManagement.cpuFreqGovernor = "powersave";

  # the manual is read elsewhere; building it is rebuild time
  documentation.nixos.enable = false;
  documentation.doc.enable = false;
  documentation.info.enable = false;

  system.stateVersion = "24.11";

  programs.git.enable = true;
  programs.git.config = {
    user.name = settings.git.name;
    user.email = settings.git.email;
    pull.rebase = true;
  };
}
