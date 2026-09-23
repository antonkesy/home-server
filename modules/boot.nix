{ ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  boot.kernelParams = [ "panic=30" ];

  # cap hung shutdowns
  systemd.settings.Manager.RebootWatchdogSec = "5min";

  boot.tmp.cleanOnBoot = true;

  # kept out of hardware-configuration.nix, which `just hardware` regenerates
  fileSystems."/".options = [ "noatime" ];
  fileSystems."/boot".options = [ "noatime" ];
}
