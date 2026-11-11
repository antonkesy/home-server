{ pkgs, ... }:

{
  # the matter controller home assistant's matter integration talks to, at
  # ws://localhost:5580/ws (the url the integration suggests). the websocket
  # has no login, so it stays off the firewall and out of settings.ports.
  # its state under /var/lib/private/matter-server is the fabric itself: lose
  # it and every device has to be paired again (lab-backup keeps it)
  services.matter-server = {
    enable = true;
    # built against a newer cryptography than upstream pins, which rejects one
    # of the PAA root certificates fetched at start; the uncaught error stopped
    # the websocket from ever opening ("Failed to connect" in home assistant).
    # an unreadable certificate is skipped instead
    package = pkgs.python-matter-server.overridePythonAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./matter-skip-bad-paa-cert.patch ];
    });
  };

  # discovery and the devices' own traffic, over ipv6 on the LAN. the NixOS
  # firewall drops inbound multicast, so mDNS answers need 5353 open; 5540 is
  # matter's operational port
  networking.firewall.allowedUDPPorts = [
    5353
    5540
  ];
}
