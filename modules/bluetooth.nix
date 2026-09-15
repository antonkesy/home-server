{ config, pkgs, ... }:

{
  # for Home Assistant BLE; no blueman, this host is headless
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
}
