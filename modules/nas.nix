{ ... }:

let
  # static DHCP lease on the Fritz!Box
  nasAddress = "192.168.178.26";

  # MyCloud keeps every share next to each other under the data volume
  share = name: {
    device = "${nasAddress}:/mnt/HD/HD_a2/${name}";
    fsType = "nfs";
    options = [
      "nfsvers=3"
      "ro" # Jellyfin only reads; metadata stays in /var/lib/jellyfin
      "soft" # fail the read instead of hanging when the NAS is off
      "timeo=100"
      "retrans=2"
      # mount on first access, drop it after 10 min idle - a boot must not
      # wait for the NAS, and the NAS may sleep
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.mount-timeout=10s"
      "_netdev"
    ];
  };
in
{
  fileSystems."/mnt/nas/Movies" = share "Movies";
  fileSystems."/mnt/nas/Music" = share "Music";
}
