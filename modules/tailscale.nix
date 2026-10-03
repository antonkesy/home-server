{ settings, ... }:

{
  services.tailscale = {
    enable = true;
    # UDP 41641 for direct connections
    openFirewall = true;
    # the subnet route below needs forwarding; also an exit node, if ever
    useRoutingFeatures = "server";
    # re-applied on every start, so a flag dropped here is dropped on the node
    extraSetFlags = [
      # pi-hole runs here: the host keeps its own resolvers, and the tailnet's
      # magic dns would overwrite them
      "--accept-dns=false"
      # the LAN behind lab; approve the route once in the admin console
      "--advertise-routes=${settings.lan.subnet}"
    ];
  };

  # a tailnet peer is a LAN peer; every service listens on 0.0.0.0 anyway
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
