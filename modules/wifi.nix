{ pkgs, settings, ... }:

let
  inherit (settings) wifi;
  # psk=<passphrase>, from `just wifi-psk`; never in the store
  secrets = "/var/lib/wifi/secrets";
in
{
  # wpa_supplicant joins on whichever wireless card shows up; dhcpcd, already
  # on for every interface, takes the lease once it is associated. a cable
  # still works alongside, with dhcpcd preferring it
  networking.wireless = {
    enable = true;
    secretsFile = secrets;
    networks.${wifi.ssid}.pskRaw = "ext:psk";
    # the regulatory domain; without it the 5 GHz channels are mostly off
    extraConfig = "country=${wifi.country}";
  };

  # the hardened unit bind-mounts the file and will not start without it. an
  # empty one until `just wifi-psk`: the network is skipped, the daemon stays
  # up. readable by its group, since the daemon runs as wpa_supplicant. here
  # rather than tmpfiles, which a first switch does not order before this
  systemd.services.wpa_supplicant.serviceConfig.ExecStartPre = [
    "+${pkgs.writeShellScript "wifi-secrets" ''
      [ -e ${secrets} ] || ${pkgs.coreutils}/bin/install -D -m 0640 -g wpa_supplicant /dev/null ${secrets}
    ''}"
  ];
}
