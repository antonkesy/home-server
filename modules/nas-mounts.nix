{ config, pkgs, ... }:

{
  # Create media directories
  systemd.tmpfiles.rules = [
    "d /mnt/music 0755 root root -"
    "d /mnt/movies 0755 root root -"
    "d /mnt/books 0755 root root -"
  ];

  # NAS mounts
  fileSystems."/mnt/music" = {
    device = "//akstorage0/music";
    fsType = "cifs";
    options = [ 
      "credentials=/etc/smb-credentials"
      "iocharset=utf8"
      "vers=3.0"
      "uid=1000"
      "gid=1000"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
    ];
  };

  fileSystems."/mnt/movies" = {
    device = "//akstorage0/movies";
    fsType = "cifs";
    options = [ 
      "credentials=/etc/smb-credentials"
      "iocharset=utf8"
      "vers=3.0"
      "uid=1000"
      "gid=1000"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
    ];
  };

  fileSystems."/mnt/books" = {
    device = "//akstorage0/ebooks";
    fsType = "cifs";
    options = [ 
      "credentials=/etc/smb-credentials"
      "iocharset=utf8"
      "vers=3.0"
      "uid=1000"
      "gid=1000"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
    ];
  };
}
