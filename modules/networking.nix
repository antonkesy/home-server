{ lib, settings, ... }:

{
  networking.hostName = settings.hostName;

  # nixos maps the hostname to 127.0.0.2; podman hands this file to pi-hole,
  # which would then serve loopback to the whole LAN
  networking.hosts = {
    "127.0.0.2" = lib.mkForce [ ];
    "${settings.lan.address}" = [
      settings.hostName
      "${settings.hostName}.${settings.lan.domain}"
    ];
  };

  # every port a service listens on is in settings.ports; jellyfin.nix adds
  # its two discovery ports to the UDP list
  networking.firewall.allowedTCPPorts = lib.attrValues settings.ports;
  networking.firewall.allowedUDPPorts = [ settings.ports.dns ];
}
