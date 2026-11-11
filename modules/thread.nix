{ settings, ... }:

let
  inherit (settings) thread;
in
{
  # the thread border router: it forms the thread network on the sonoff
  # dongle plus mg24 (settings.usb) and routes it onto the LAN, so
  # matter-server (modules/matter.nix) reaches thread devices like wi-fi ones.
  # home assistant's otbr integration manages it over the rest api at
  # http://127.0.0.1:8081, which has no login, so it stays off the firewall
  # and out of settings.ports; no web ui. its state under /var/lib/thread is
  # the network itself, key included: lose it and every thread device has to
  # join again (lab-backup keeps it)
  services.openthread-border-router = {
    enable = true;
    # needs the openthread rcp firmware, not the zigbee one the dongle may
    # ship with; `just thread-radio` says which it runs
    radio = {
      device = thread.radio;
      inherit (thread) baudRate flowControl;
    };
    # the routes to the mesh are advertised on lab's link to the LAN
    backboneInterfaces = [ thread.backbone ];
  };

  # mDNS, for the border router's own advertisement and for the services of
  # thread devices; also opened by matter.nix
  networking.firewall.allowedUDPPorts = [ 5353 ];
}
