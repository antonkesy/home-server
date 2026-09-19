{ lib, settings, ... }:

let
  inherit (settings) nas;

  share = name: {
    device = "//${nas.address}/${name}";
    fsType = "cifs";
    options = [
      # the automount simply fails until `just nas-credentials` has run
      "credentials=${nas.credentials}"
      "vers=3.0"
      "iocharset=utf8"
      # cifs has no per-user ownership: everything belongs to ak, world-readable for jellyfin
      "uid=${settings.user}"
      "gid=${settings.group}"
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
  fileSystems = lib.listToAttrs (
    map (name: lib.nameValuePair "${nas.mountRoot}/${name}" (share name)) nas.shares
  );
}
