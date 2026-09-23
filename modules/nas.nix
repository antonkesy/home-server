{ lib, settings, ... }:

let
  inherit (settings) nas;

  share = name: {
    device = "//${nas.address}/${name}";
    fsType = "cifs";
    options = [
      # fails until `just nas-credentials` has run
      "credentials=${nas.credentials}"
      "vers=3.0"
      "iocharset=utf8"
      # cifs has no per-user ownership; chown/chmod are no-ops
      "uid=${settings.user}"
      "gid=${settings.group}"
      "file_mode=0664"
      "dir_mode=0775"
      "soft" # fail instead of hanging when the NAS is off
      # mount on first access; a boot must not wait for the NAS
      "noauto"
      "nofail"
      "x-systemd.automount"
      "x-systemd.mount-timeout=10s"
      "_netdev"
    ]
    # let the NAS sleep; nas.keepMounted says which shares may not
    ++ lib.optional (!(lib.elem name nas.keepMounted)) "x-systemd.idle-timeout=600";
  };
in
{
  fileSystems = lib.listToAttrs (
    map (name: lib.nameValuePair "${nas.mountRoot}/${name}" (share name)) nas.shares
  );
}
