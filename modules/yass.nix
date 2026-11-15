{
  config,
  lib,
  settings,
  yass,
  ...
}:

let
  inherit (settings) paperless;

  # "save to server" drops the pdf where paperless picks it up (modules/paperless.nix)
  consume = "${paperless.dir}/consume";
in
{
  imports = [ yass.nixosModules.default ];

  # the scanner over usb: sane's epsonds backend knows the DS-530 II, and its
  # udev rules hand the device to the scanner group the yass user is in
  hardware.sane.enable = true;

  services.yass = {
    enable = true;
    settings = {
      # no authentication; reachable like every other port, on the LAN and the
      # tailnet only (modules/proxy.nix)
      server.listen = "0.0.0.0:${toString settings.ports.yass}";
      scanner.device = settings.yass.device;
      scanner.defaults.source = settings.yass.source;
      output.directory = consume;
    };
  };

  # consume/ is ak:lab, setgid with a group-writable default acl
  # (modules/storage.nix), so paperless can delete what yass leaves there
  users.users.yass.extraGroups = [ settings.group ];

  # ReadWritePaths on a missing consume/ fails the unit before it starts;
  # paperless-storage-dirs waits for the array and creates it
  systemd.services.yass = {
    # upstream's module points sane at /etc/sane.d, which nixos does not
    # have; without its dll.conf sane loads no backend and finds no scanner
    environment.SANE_CONFIG_DIR = lib.mkForce config.environment.sessionVariables.SANE_CONFIG_DIR;
    requires = [ "paperless-storage-dirs.service" ];
    after = [ "paperless-storage-dirs.service" ];
    unitConfig.RequiresMountsFor = [ consume ];
  };
}
