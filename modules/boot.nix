{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Keep enough generations to roll back to, without filling /boot.
  boot.loader.systemd-boot.configurationLimit = 10;

  # Bootspec documents each generation in a machine-readable form; required by
  # tooling like lanzaboote and by systemd-boot boot counting.
  boot.bootspec.enable = true;

  # Reboot 30s after a kernel panic instead of sitting dead until someone
  # walks over to the machine.
  boot.kernelParams = [ "panic=30" ];

  # Bound how long a hung shutdown may block a reboot. Without this a stuck
  # unit can wedge the box indefinitely on `reboot`.
  systemd.settings.Manager.RebootWatchdogSec = "5min";

  # A runtime watchdog resets the board if the kernel stops petting /dev/watchdog.
  # Left off by default: on hardware with a flaky watchdog driver it causes
  # spurious reboots, which is worse than a hang you can power-cycle. Enable it
  # once you have confirmed `wdctl` reports a working device.
  # systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  boot.tmp.cleanOnBoot = true;
}
