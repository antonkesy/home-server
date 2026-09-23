{ lib, settings, ... }:

{
  networking.hostName = settings.hostName;

  # podman copies this file into the Pi-hole container, where FTL serves it to
  # the whole LAN - the NixOS default (127.0.0.2 lab) makes every client
  # resolve `lab` to its own loopback
  networking.hosts = {
    "127.0.0.2" = lib.mkForce [ ];
    "${settings.lan.address}" = [
      settings.hostName
      "${settings.hostName}.${settings.lan.domain}"
    ];
  };

  # the on-demand backends (settings.onDemand) stay closed on purpose
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = lib.attrValues settings.ports;
  networking.firewall.allowedUDPPorts = [ settings.ports.dns ];
}
