{ ... }:

let
  # static DHCP lease on the Fritz!Box
  nasAddress = "192.168.178.26";

  # written once by `just nas-credentials`; the automount simply fails until then
  credentials = "/var/lib/nas/credentials";

  share = name: {
    device = "//${nasAddress}/${name}";
    fsType = "cifs";
    options = [
      "credentials=${credentials}"
      "vers=3.0"
      "iocharset=utf8"
      # cifs has no per-user ownership: everything belongs to ak, world-readable for jellyfin
      "uid=ak"
      "gid=lab"
      "file_mode=0664"
      "dir_mode=0775"
      "rw"
      "soft" # fail instead of hanging when the NAS is off
      # mount on first access, drop it after 10 min idle - a boot must not
      # wait for the NAS, and the NAS may sleep
      "noauto"
      "nofail"
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
  fileSystems."/mnt/nas/Shows" = share "Shows";
  fileSystems."/mnt/nas/ak" = share "ak";
}
