{
  config,
  pkgs,
  settings,
  ...
}:

let
  inherit (settings) thread;
  otbr = config.services.openthread-border-router.package;
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

  # with no IPv6 from the router, the border router advertises an on-link
  # prefix of its own, and phones take their addresses from it. the kernel
  # ignores lab's own advertisements, so lab has no route back: the
  # reverse-path filter drops their packets to the mesh, and android hangs at
  # "checking connectivity to thread network". re-added every minute, since a
  # link flap takes it away; with IPv6 from the router it is merely unused
  systemd.services.thread-onlink-route = {
    wantedBy = [ "multi-user.target" ];
    after = [ "otbr-agent.service" ];
    path = [
      otbr
      pkgs.iproute2
    ];
    serviceConfig.Restart = "always";
    script = ''
      while true; do
        prefix=$(ot-ctl br onlinkprefix 2>/dev/null | tr -d '\r' | sed -n 's/^Local: //p')
        [ -z "$prefix" ] || ip -6 route replace "$prefix" dev ${thread.backbone} || true
        sleep 60
      done
    '';
  };
}
