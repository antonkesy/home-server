{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  mcfg = settings.musicGrabber;
  port = settings.ports.musicGrabber;
  stateDir = "/var/lib/musicgrabber";
  uid = toString config.users.users.${settings.user}.uid;
  # the oci-containers module's RuntimeDirectory is the container name
  envFile = "/run/musicgrabber/env";

  # ak's uid is fixed (modules/users.nix), lab's gid is allocated by nixos
  pgid = pkgs.writeShellScript "musicgrabber-pgid" ''
    printf 'PGID=%s\n' "$(${lib.getExe pkgs.getent} group ${settings.group} | cut -d: -f3)" \
      > ${envFile}
  '';
in
{
  assertions = [
    {
      assertion =
        lib.elem (baseNameOf mcfg.dir) settings.storage.dirs && dirOf mcfg.dir == settings.storage.root;
      message = "settings.musicGrabber.dir must be one of storage.dirs";
    }
  ];

  # pihole pattern: the container runs as ak, so its state dir is his
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 ${uid} ${uid} -"
  ];

  virtualisation.oci-containers.containers.musicgrabber = {
    image = mcfg.image;

    environment = {
      TZ = config.time.timeZone;
      MUSIC_DIR = "/music";
      DB_PATH = "/data/music_grabber.db";
      ENABLE_MUSICBRAINZ = "true";
      # upstream: Albums/ and Singles/ under the library. "." is the root, so
      # albums and album-attributed singles land in <Artist>/<Album>/, the
      # layout jellyfin expects; a single without album context in <Artist>/
      ALBUMS_SUBDIR = ".";
      SINGLES_SUBDIR = ".";
      AUTO_ALBUM_SINGLES = "true";
      # downloads are chowned to this; the group comes from the env file
      PUID = uid;
      # upstream: 666. group-writable is the rule on the array (modules/storage.nix)
      FILE_PERMISSIONS = "664";
    };
    environmentFiles = [ envFile ];

    volumes = [
      "${mcfg.dir}:/music"
      "${stateDir}:/data"
    ];

    ports = [ "${toString port}:8080/tcp" ];

    # upstream compose
    extraOptions = [ "--shm-size=2g" ];
  };

  systemd.services.podman-musicgrabber = {
    # a bind of an unmounted array would build Music/ on the SSD
    unitConfig.RequiresMountsFor = [ mcfg.dir ];
    path = [ pkgs.coreutils ];
    serviceConfig.ExecStartPre = lib.mkBefore [ "${pgid}" ];
  };
}
