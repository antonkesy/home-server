{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.bootspec.enable = true;

  # reboot 30s after panic
  boot.kernelParams = [ "panic=30" ];

  # cap hung shutdowns
  systemd.settings.Manager.RebootWatchdogSec = "5min";

  # spurious reboots on flaky watchdog drivers; check `wdctl` first
  # systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  boot.tmp.cleanOnBoot = true;
}
